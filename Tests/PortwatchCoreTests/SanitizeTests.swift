@testable import PortwatchCore
import Testing

struct SanitizeTests {
    @Test func replacesEscapeAndOtherControlCharacters() {
        #expect(Sanitize.displayText("a\u{1B}[31mb") == "a\u{FFFD}[31mb")
        #expect(Sanitize.displayText("a\u{07}b") == "a\u{FFFD}b") // BEL
        #expect(Sanitize.displayText("a\u{7F}b") == "a\u{FFFD}b") // DEL
        #expect(Sanitize.displayText("a\tb") == "a\u{FFFD}b")
    }

    @Test func replacesTheOscTitleSequenceThatReachedTheTerminalInTheAudit() {
        let hostile = "proj\u{1B}]0;PWNED\u{07}x"
        let scrubbed = Sanitize.displayText(hostile)
        #expect(!scrubbed.unicodeScalars.contains { $0.value < 0x20 })
    }

    @Test func replacesC1ControlsIncludingTheSingleByteCsi() {
        #expect(Sanitize.displayText("a\u{9B}31mb") == "a\u{FFFD}31mb")
        #expect(Sanitize.displayText("a\u{9D}b") == "a\u{FFFD}b") // single-byte OSC
    }

    @Test func replacesEachScalarOfACrLfSoNothingCanMoveTheCursor() {
        #expect(Sanitize.displayText("a\r\nb") == "a\u{FFFD}\u{FFFD}b")
    }

    @Test func replacesLineAndParagraphSeparators() {
        #expect(Sanitize.displayText("a\u{2028}b\u{2029}c") == "a\u{FFFD}b\u{FFFD}c")
    }

    @Test func replacesBidirectionalOverridesThatCanReorderWhatYouSee() throws {
        for scalar in [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x200E, 0x200F, 0x061C] {
            let text = try "a" + String(#require(UnicodeScalar(scalar))) + "b"
            #expect(Sanitize.displayText(text) == "a\u{FFFD}b", "U+\(String(scalar, radix: 16)) should be replaced")
        }
    }

    @Test func leavesOrdinaryTextAlone() {
        for text in ["node", "Google Drive", "/Users/andy/Work/app", "café", "日本語", "🚀 launch", "e\u{301}", "a-b_c.d"] {
            #expect(Sanitize.displayText(text) == text)
        }
    }

    @Test func keepsEmojiJoinersWhichAreHarmless() {
        let family = "👨\u{200D}👩\u{200D}👧"
        #expect(Sanitize.displayText(family) == family)
    }

    @Test func emptyStaysEmpty() {
        #expect(Sanitize.displayText("").isEmpty)
    }
}
