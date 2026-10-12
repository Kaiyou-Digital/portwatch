public enum Filters {
    public static let minPort = 1024

    /// Common macOS system daemons that listen on user-range ports. Hardcoded and
    /// not affected by show-all; the user's own exclusions live in `ExcludeStore`.
    public static let excludedProcessNames: Set<String> = [
        "rapportd",
        "ControlCenter",
        "mDNSResponder",
        "sharingd",
        "identityservicesd",
    ]

    public static func isFiltered(port: Int, name: String) -> Bool {
        port < minPort || excludedProcessNames.contains(name)
    }
}
