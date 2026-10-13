import Foundation
@testable import PortwatchCore
import Testing

struct CollectorTests {
    let now = Date(timeIntervalSince1970: 10000)

    @Test func filtersFormatsAndSortsByPort() throws {
        let source = FakeSource(services: [
            raw(1, "b", port: 9000, start: Date(timeIntervalSince1970: 10000 - 65)),
            raw(2, "rapportd", port: 5000),
            raw(3, "low", port: 80),
            raw(4, "a", port: 3000, cwd: "/proj", start: Date(timeIntervalSince1970: 10000 - 3600)),
        ])

        let result = try collectServices(from: source, now: now)

        #expect(result == [
            Service(pid: 4, process: "a", port: 3000, source: "/proj", uptime: "01:00:00"),
            Service(pid: 1, process: "b", port: 9000, source: "/work", uptime: "01:05"),
        ])
    }

    @Test func tiesOnPortBreakByPid() throws {
        let source = FakeSource(services: [raw(9, "x", port: 4000), raw(2, "y", port: 4000)])
        #expect(try collectServices(from: source, now: now).map(\.pid) == [2, 9])
    }

    @Test func emptyIsEmpty() throws {
        #expect(try collectServices(from: FakeSource(), now: now).isEmpty)
    }

    @Test func sourceErrorsPropagate() {
        struct Boom: Error {}
        #expect(throws: Boom.self) { try collectServices(from: FakeSource(error: Boom()), now: now) }
    }

    @Test func scrubsHostileProcessNamesAndDirectoriesFromOtherProcesses() throws {
        let source = FakeSource(services: [
            raw(1, "evil\u{1B}]0;PWNED\u{07}", port: 4000, cwd: "/work/proj\u{1B}[31m\r\nfake"),
        ])
        let result = try collectServices(from: source, now: now)
        #expect(result.count == 1)
        #expect(result[0].process == "evil\u{FFFD}]0;PWNED\u{FFFD}")
        #expect(result[0].source == "/work/proj\u{FFFD}[31m\u{FFFD}\u{FFFD}fake")
    }

    @Test func systemDaemonFilteringStillUsesTheRealName() throws {
        let source = FakeSource(services: [raw(1, "rapportd", port: 5000), raw(2, "ok", port: 5001)])
        #expect(try collectServices(from: source, now: now).map(\.process) == ["ok"])
    }
}
