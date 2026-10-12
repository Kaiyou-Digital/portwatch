import Darwin
import Foundation

/// Reads listening TCP sockets straight from libproc, with no subprocesses.
/// This is the only file that touches libproc.
///
/// Verified on macOS against `lsof -iTCP -sTCP:LISTEN` run unprivileged: both
/// see the same set of (pid, port) pairs, i.e. only the current user's
/// processes. The process name comes from `proc_name`, not `pbi_comm`, which
/// truncates at 16 characters (`identityservicesd` is 17).
public struct LibprocSource: ProcessSource {
    public init() {}

    public func listeningServices() throws -> [RawService] {
        var services: [RawService] = []
        for pid in allPids() {
            let ports = listeningPorts(of: pid)
            if ports.isEmpty {
                continue
            }
            // Dropped, like the Node version, if the cwd or start time can't be read.
            guard let cwd = workingDirectory(of: pid), let start = startTime(of: pid) else { continue }
            let name = processName(of: pid)
            for port in ports.sorted() {
                services.append(RawService(pid: pid, port: port, name: name, cwd: cwd, startTime: start))
            }
        }
        return services
    }

    private func allPids() -> [Int32] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var buffer = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 64)
        let size = Int32(buffer.count * MemoryLayout<Int32>.size)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, size)
        guard written > 0 else { return [] }
        return buffer.prefix(Int(written) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }

    /// Distinct listening TCP ports for a pid. A dual-stack listener shows up
    /// once per address family; the set collapses those.
    private func listeningPorts(of pid: Int32) -> Set<Int> {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / MemoryLayout<proc_fdinfo>.size + 8)
        let size = Int32(fds.count * MemoryLayout<proc_fdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
        guard written > 0 else { return [] }

        let sockets = fds.prefix(Int(written) / MemoryLayout<proc_fdinfo>.size)
            .filter { $0.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) }

        var ports = Set<Int>()
        for fd in sockets {
            var info = socket_fdinfo()
            let read = proc_pidfdinfo(
                pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size)
            )
            guard read > 0,
                  info.psi.soi_kind == Int32(SOCKINFO_TCP),
                  info.psi.soi_proto.pri_tcp.tcpsi_state == Int32(TSI_S_LISTEN)
            else { continue }
            // The port is stored in network byte order.
            let raw = UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
            ports.insert(Int(UInt16(bigEndian: raw)))
        }
        return ports
    }

    private func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let read = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard read > 0 else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: UInt8.self, capacity: Int(MAXPATHLEN)) {
                String(
                    decoding: UnsafeBufferPointer(start: $0, count: Int(MAXPATHLEN)).prefix { $0 != 0 },
                    as: UTF8.self
                )
            }
        }
    }

    private func startTime(of pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard read > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    private func processName(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
