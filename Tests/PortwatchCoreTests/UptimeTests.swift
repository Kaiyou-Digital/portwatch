@testable import PortwatchCore
import Testing

struct UptimeTests {
    @Test func formatsLikePsEtime() {
        #expect(Uptime.format(seconds: 0) == "00:00")
        #expect(Uptime.format(seconds: 59) == "00:59")
        #expect(Uptime.format(seconds: 65) == "01:05")
        #expect(Uptime.format(seconds: 3600) == "01:00:00")
        #expect(Uptime.format(seconds: 7778) == "02:09:38")
        #expect(Uptime.format(seconds: 86400) == "01-00:00:00")
        #expect(Uptime.format(seconds: 165_746) == "01-22:02:26")
        #expect(Uptime.format(seconds: 100 * 86400) == "100-00:00:00")
    }

    @Test func negativeElapsedTimeClampsToZero() {
        #expect(Uptime.format(seconds: -5) == "00:00")
    }
}
