import Foundation
@testable import PortwatchCore
import Testing

struct ExcludeStoreTests {
    func tempStore() -> ExcludeStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return ExcludeStore(url: dir.appendingPathComponent("nested/excludes.json"))
    }

    @Test func missingFileIsEmpty() throws {
        #expect(try tempStore().load().isEmpty)
    }

    @Test func roundTripsAndCreatesDirectories() throws {
        let store = tempStore()
        try store.save(["node", "Google Drive"])
        #expect(try store.load() == ["node", "Google Drive"])
    }

    @Test func writesTheSortedPrettyArrayTheNodeVersionWrote() throws {
        let store = tempStore()
        try store.save(["node", "Helm"])
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "[\n  \"Helm\",\n  \"node\"\n]")
    }

    @Test func readsAFileWrittenByTheNodeVersion() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("[\n  \"Helm\",\n  \"node\"\n]".utf8).write(to: store.url)
        #expect(try store.load() == ["Helm", "node"])
    }

    @Test func emptyListWritesEmptyArray() throws {
        let store = tempStore()
        try store.save([])
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "[]")
    }

    @Test func corruptFileThrows() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
    }

    @Test func defaultPathHonoursHome() {
        #expect(ExcludeStore.defaultURL(environment: ["HOME": "/tmp/h"])
            .path == "/tmp/h/.config/portwatch/excludes.json")
    }

    @Test func defaultPathFallsBackToTheAccountHomeWhenHomeIsUnsetOrEmpty() {
        let expected = NSHomeDirectory() + "/.config/portwatch/excludes.json"
        #expect(ExcludeStore.defaultURL(environment: [:]).path == expected)
        #expect(ExcludeStore.defaultURL(environment: ["HOME": ""]).path == expected)
    }
}
