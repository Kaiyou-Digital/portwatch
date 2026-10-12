@testable import PortwatchCore
import Testing

struct GroupingTests {
    @Test func groupsPortsByPid() {
        let groups = groupServices([
            service(7, "mysqld", port: 3306, uptime: "05:00"),
            service(8, "node", port: 4000),
            service(7, "mysqld", port: 33060, uptime: "05:00"),
        ])

        #expect(groups.count == 2)
        #expect(groups[0].pid == 7)
        #expect(groups[0].ports.map(\.port) == [3306, 33060])
        #expect(groups[1].pid == 8)
    }

    @Test func groupsOrderByLowestPort() {
        let groups = groupServices([
            service(2, port: 3000), service(1, port: 4000), service(2, port: 5000),
        ])
        #expect(groups.map(\.pid) == [2, 1])
    }

    @Test func flattenKeepsDisplayOrderAndKeys() {
        let rows = flattenGroups(groupServices([service(7, port: 1), service(7, port: 2), service(8, port: 3)]))
        #expect(rows.map(\.key) == ["7:1", "7:2", "8:3"])
    }
}
