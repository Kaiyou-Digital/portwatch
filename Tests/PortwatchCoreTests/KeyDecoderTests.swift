@testable import PortwatchCore
import Testing

struct KeyDecoderTests {
    @Test func decodesPlainKeys() {
        #expect(KeyDecoder.decode(Array("jkxeaqyn".utf8)) == "jkxeaqyn".map { .char($0) })
    }

    @Test func decodesArrowsInBothEscapeForms() {
        #expect(KeyDecoder.decode([0x1B, 0x5B, 0x41]) == [.up])
        #expect(KeyDecoder.decode([0x1B, 0x5B, 0x42]) == [.down])
        #expect(KeyDecoder.decode([0x1B, 0x4F, 0x41]) == [.up])
    }

    @Test func decodesCtrlC() {
        #expect(KeyDecoder.decode([0x03]) == [.ctrlC])
    }

    @Test func handlesSeveralKeysInOneRead() {
        #expect(KeyDecoder.decode([0x6A, 0x1B, 0x5B, 0x42, 0x6B]) == [.char("j"), .down, .char("k")])
    }

    @Test func dropsUnknownSequencesAndControlBytes() {
        #expect(KeyDecoder.decode([0x1B]).isEmpty)
        #expect(KeyDecoder.decode([0x1B, 0x5B, 0x43]).isEmpty) // right arrow
        #expect(KeyDecoder.decode([0x0D, 0x7F, 0x09]).isEmpty)
    }

    @Test func decodesMultibyteText() {
        #expect(KeyDecoder.decode(Array("é".utf8)) == [.char("é")])
    }
}
