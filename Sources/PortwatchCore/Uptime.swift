import Foundation

public enum Uptime {
    /// Formats elapsed seconds the way `ps -o etime` does: `[[dd-]hh:]mm:ss`,
    /// so the display is unchanged from the Node version.
    public static func format(seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if days > 0 {
            return String(format: "%02d-%02d:%02d:%02d", days, hours, minutes, secs)
        }
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    public static func format(since start: Date, now: Date) -> String {
        format(seconds: Int(now.timeIntervalSince(start)))
    }
}
