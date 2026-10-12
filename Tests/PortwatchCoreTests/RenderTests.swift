@testable import PortwatchCore
import Testing

struct RenderTests {
    func plain(_ state: AppState, height: Int = 30) -> [String] {
        Renderer.lines(for: state, height: height).map(\.plainText)
    }

    func state(_ services: [Service], excludes: Set<String> = []) -> AppState {
        var state = AppState()
        _ = state.apply(.excludesLoaded(excludes))
        _ = state.apply(.tickSucceeded(services))
        return state
    }

    @Test func padTruncatesFromTheEndLeavingATrailingSpace() {
        #expect(Renderer.pad("ab", 5) == "ab   ")
        #expect(Renderer.pad("abcde", 5) == "abcd ")
        #expect(Renderer.pad("abcdefgh", 5) == "abcd ")
    }

    @Test func padLeftTruncateKeepsTheTail() {
        #expect(Renderer.padLeftTruncate("/a", 6) == "/a    ")
        #expect(Renderer.padLeftTruncate("/very/long/path", 8) == "…g/path ")
    }

    @Test func distinctDeepPathsStayDistinguishable() {
        let a = Renderer.padLeftTruncate("/same/long/common/prefix/project-a", 20)
        let b = Renderer.padLeftTruncate("/same/long/common/prefix/project-b", 20)
        #expect(a != b)
    }

    @Test func headerAndSingleRowUseTheNodeColumnOrder() {
        let lines = plain(state([service(8927, "Helm", port: 8927, source: "/x", uptime: "02:09:38")]))
        #expect(lines[0] == "PROCESS             PORT    PID     SOURCE                                      UPTIME")
        #expect(lines[1] == "Helm                8927    8927    /x                                          02:09:38")
    }

    @Test func multiPortProcessGetsAHeadingAndIndentedRows() {
        let lines = plain(state([
            service(7, "mysqld", port: 3306, source: "/db", uptime: "05:00"),
            service(7, "mysqld", port: 33060, source: "/db", uptime: "05:00"),
        ]))
        #expect(lines[1].hasPrefix("mysqld              "))
        #expect(lines[1].contains("7       /db"))
        #expect(lines[2].hasPrefix("                    3306    "))
        #expect(lines[2].hasSuffix("05:00"))
        #expect(lines[3].hasPrefix("                    33060   "))
    }

    @Test func selectedRowIsInverseAndExcludedRowsAreDimmedAndTagged() {
        var s = state([service(1, "a", port: 3000), service(2, "b", port: 4000)], excludes: ["b"])
        _ = s.apply(.key(.char("a"))) // show all
        let lines = Renderer.lines(for: s, height: 30)
        // Computed outside #expect: the macro can't type-check a key path passed to allSatisfy.
        let selectedIsInverse = lines[1].cells.allSatisfy(\.style.inverse)
        let excludedIsDimOnly = lines[2].cells.allSatisfy { $0.style.dim && !$0.style.inverse }
        #expect(selectedIsInverse)
        #expect(excludedIsDimOnly)
        #expect(lines.last?.plainText.hasSuffix("[showing excluded]") == true)
    }

    @Test func excludedMultiPortHeadingCarriesTheTag() {
        var s = state([service(7, "m", port: 1024), service(7, "m", port: 1025)], excludes: ["m"])
        _ = s.apply(.key(.char("a")))
        #expect(plain(s)[1].hasSuffix("(excluded)"))
    }

    @Test func footerShowsErrorThenHint() {
        var s = state([service()])
        _ = s.apply(.tickFailed("boom"))
        let lines = plain(s)
        #expect(lines[lines.count - 2] == "Error: boom")
        #expect(lines.last == Renderer.footerHint)
    }

    @Test func confirmPromptReplacesTheHint() {
        var s = state([service(42, "node")])
        _ = s.apply(.key(.char("x")))
        #expect(plain(s).last == "Kill node (PID 42)? y/n")
    }

    @Test func tallListsScrollToKeepTheSelectionVisible() {
        let many = (0 ..< 20).map { service(Int32($0 + 1), "p\($0)", port: 3000 + $0) }
        var s = state(many)
        for _ in 0 ..< 15 {
            _ = s.apply(.key(.char("j")))
        }
        let lines = Renderer.lines(for: s, height: 8)
        #expect(lines.count == 8)
        #expect(lines[0].plainText.hasPrefix("PROCESS"))
        #expect(lines.contains { $0.cells.contains { $0.style.inverse && $0.text.hasPrefix("p15") } })
        #expect(lines.last?.plainText == Renderer.footerHint)
    }

    @Test func ansiClipsToWidthAndResetsStyles() {
        let line = StyledLine([Cell("hello", Style(bold: true)), Cell(" world")])
        #expect(line.ansi(width: 100) == "\u{1B}[1mhello\u{1B}[0m world")
        #expect(line.ansi(width: 7) == "\u{1B}[1mhello\u{1B}[0m w")
        #expect(line.ansi(width: 0) == "")
    }
}
