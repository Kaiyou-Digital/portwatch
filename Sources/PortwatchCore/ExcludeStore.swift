import Foundation

/// Persists the user's own process-name exclusions. The file format is shared
/// with the Node version: a JSON array of names, sorted, pretty-printed.
public struct ExcludeStore: Sendable {
    public var url: URL

    /// `$HOME` wins over the account's home directory, matching `os.homedir()` in
    /// the Node version, so tests and sandboxes can redirect the file.
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/portwatch/excludes.json")
    }

    public init(url: URL = ExcludeStore.defaultURL()) {
        self.url = url
    }

    /// A missing file is an empty list; anything else unreadable throws.
    public func load() throws -> Set<String> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        return try Set(JSONDecoder().decode([String].self, from: data))
    }

    public func save(_ names: Set<String>) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sorted = names.sorted()
        let data: Data
        if sorted.isEmpty {
            data = Data("[]".utf8)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            data = try encoder.encode(sorted)
        }
        try data.write(to: url, options: .atomic)
    }
}
