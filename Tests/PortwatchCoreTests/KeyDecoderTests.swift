@testable import PortwatchCore
import Testing

struct KeyDecoderTests {
    private func decode(_ bytes: [UInt8]) -> [Key] {
        var decoder = KeyDecoder()
        return decoder.decode(bytes)
    }

    private func decode(_ text: String) -> [Key] {
        decode(Array(text.utf8))
    }

    private let pasteStart = "\u{1B}[200~"
    private let pasteEnd = "\u{1B}[201~"

    @Test func decodesPlainKeys() {
        #expect(decode("jkxeaqyn") == "jkxeaqyn".map { .char($0) })
    }

    @Test func decodesArrowsInBothEscapeForms() {
        #expect(decode([0x1B, 0x5B, 0x41]) == [.up])
        #expect(decode([0x1B, 0x5B, 0x42]) == [.down])
        #expect(decode([0x1B, 0x4F, 0x41]) == [.up])
        #expect(decode([0x1B, 0x4F, 0x42]) == [.down])
    }

    @Test func decodesCtrlC() {
        #expect(decode([0x03]) == [.ctrlC])
    }

    @Test func handlesSeveralKeysInOneRead() {
        #expect(decode([0x6A, 0x1B, 0x5B, 0x42, 0x6B]) == [.char("j"), .down, .char("k")])
    }

    @Test func dropsUnknownSequencesAndControlBytes() {
        #expect(decode([0x1B]).isEmpty)
        #expect(decode([0x1B, 0x5B, 0x43]).isEmpty) // right arrow
        #expect(decode([0x0D, 0x7F, 0x09]).isEmpty)
    }

    @Test func decodesMultibyteText() {
        #expect(decode("é") == [.char("é")])
    }

    // MARK: sequences are consumed whole, so their tails never leak out as keys

    @Test func consumesLongerEscapeSequencesWholeSoTheirTailsAreNotKeys() {
        #expect(decode("\u{1B}[1;5A").isEmpty) // ctrl+up: no stray ';', '5' or 'A'
        #expect(decode("\u{1B}[3~").isEmpty) // delete: no stray '3' or '~'
        #expect(decode("\u{1B}[<0;10;5M").isEmpty) // a mouse report
        #expect(decode("j\u{1B}[3~k") == [.char("j"), .char("k")])
    }

    @Test func aBareEscDoesNotSwallowTheNextKeypress() {
        // Esc, then a separate read later: the Esc is dropped but the key still works.
        var decoder = KeyDecoder()
        #expect(decoder.decode([0x1B]).isEmpty)
        #expect(decoder.decode(Array("x".utf8)) == [.char("x")])
        // Alt+key arrives as ESC + key in one read; it is just the key (bursts are handled by the reducer).
        #expect(decode("\u{1B}j") == [.char("j")])
    }

    @Test func aSequenceSplitAcrossReadsStillDecodes() {
        var decoder = KeyDecoder()
        #expect(decoder.decode([0x1B]).isEmpty)
        #expect(decoder.decode([0x5B]).isEmpty)
        #expect(decoder.decode([0x41]) == [.up])
    }

    // MARK: bracketed paste

    @Test func pastedTextIsDroppedEntirely() {
        #expect(decode(pasteStart + "xy" + pasteEnd).isEmpty)
        #expect(decode(pasteStart + "proxy the quick brown fox" + pasteEnd).isEmpty)
    }

    @Test func keysAroundAPasteAreKept() {
        #expect(decode("j" + pasteStart + "xyxyxy" + pasteEnd + "k") == [.char("j"), .char("k")])
    }

    @Test func pasteMarkersSplitAcrossReadsAreStillRecognised() {
        var decoder = KeyDecoder()
        #expect(decoder.decode(Array("\u{1B}[2".utf8)).isEmpty)
        #expect(decoder.decode(Array("00~xy".utf8)).isEmpty)
        #expect(decoder.decode(Array("more xy".utf8)).isEmpty) // still inside the paste
        #expect(decoder.decode(Array("\u{1B}[20".utf8)).isEmpty)
        #expect(decoder.decode(Array("1~j".utf8)) == [.char("j")])
    }

    @Test func escapeSequencesInsideAPasteAreDroppedToo() {
        #expect(decode(pasteStart + "\u{1B}[A\u{1B}[B" + pasteEnd).isEmpty)
    }

    @Test func ctrlCStillQuitsInsideAPasteSoAnUnterminatedPasteCannotTrapYou() {
        var decoder = KeyDecoder()
        #expect(decoder.decode(Array(pasteStart.utf8) + Array("xy".utf8)).isEmpty)
        #expect(decoder.decode([0x03]) == [.ctrlC])
    }

    @Test func normalKeysWorkAgainAfterAPasteEnds() {
        var decoder = KeyDecoder()
        _ = decoder.decode(Array((pasteStart + "xy" + pasteEnd).utf8))
        #expect(decoder.decode(Array("x".utf8)) == [.char("x")])
    }

    @Test func aStrayPasteEndMarkerOutsideAPasteIsIgnored() {
        #expect(decode(pasteEnd + "j") == [.char("j")])
    }
}
