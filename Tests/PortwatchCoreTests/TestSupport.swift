import Foundation
@testable import PortwatchCore

func service(
    _ pid: Int32 = 100, _ process: String = "node", port: Int = 3000,
    source: String = "/work/app", uptime: String = "01:00"
) -> Service {
    Service(pid: pid, process: process, port: port, source: source, uptime: uptime)
}

struct FakeSource: ProcessSource {
    var services: [RawService] = []
    var error: (any Error)?

    func listeningServices() throws -> [RawService] {
        if let error {
            throw error
        }
        return services
    }
}

func raw(
    _ pid: Int32, _ name: String, port: Int, cwd: String = "/work", start: Date = Date(timeIntervalSince1970: 0)
) -> RawService {
    RawService(pid: pid, port: port, name: name, cwd: cwd, startTime: start)
}
