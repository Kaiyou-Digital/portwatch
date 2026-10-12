@testable import PortwatchCore
import Testing

struct FiltersTests {
    @Test func dropsPrivilegedPorts() {
        #expect(Filters.isFiltered(port: 80, name: "nginx"))
        #expect(Filters.isFiltered(port: 1023, name: "x"))
        #expect(!Filters.isFiltered(port: 1024, name: "x"))
    }

    @Test func dropsSystemDaemonsByName() {
        for name in ["rapportd", "ControlCenter", "mDNSResponder", "sharingd", "identityservicesd"] {
            #expect(Filters.isFiltered(port: 5000, name: name))
        }
        #expect(!Filters.isFiltered(port: 5000, name: "node"))
    }
}
