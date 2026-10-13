import Foundation

/// The seam between the pure logic and the operating system. The real
/// implementation is `LibprocSource`; tests use a fake.
public protocol ProcessSource: Sendable {
    /// Every listening TCP port visible to the current user. A process that
    /// can't be fully inspected (exited mid-read, permission denied) is
    /// omitted rather than failing the whole call.
    func listeningServices() throws -> [RawService]
}

/// Reads, filters, formats and sorts (by port, then pid) one refresh tick's worth of services.
public func collectServices(from source: ProcessSource, now: Date = Date()) throws -> [Service] {
    try source.listeningServices()
        .filter { !Filters.isFiltered(port: $0.port, name: $0.name) }
        .map {
            Service(
                pid: $0.pid,
                process: Sanitize.displayText($0.name),
                port: $0.port,
                source: Sanitize.displayText($0.cwd),
                uptime: Uptime.format(since: $0.startTime, now: now)
            )
        }
        .sorted { $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid }
}
