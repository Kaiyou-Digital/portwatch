/// Decodes raw terminal input into keys. Stateful because two things span reads:
/// an escape sequence split across two reads, and a bracketed paste (the terminal
/// wraps pasted text in `ESC [ 200 ~` ... `ESC [ 201 ~`), whose content must be
/// dropped so pasted text can never be mistaken for keypresses.
///
/// Escape sequences are consumed whole, so their tails never leak out as keys.
public struct KeyDecoder: Sendable {
    private var pending: [UInt8] = []
    private var inPaste = false

    /// A CSI sequence longer than this without a final byte is garbage, not input to wait for.
    private static let maxSequenceLength = 64

    public init() {}

    public mutating func decode(_ bytes: [UInt8]) -> [Key] {
        let buffer = pending + bytes
        pending = []
        var keys: [Key] = []
        var index = 0

        while index < buffer.count {
            let byte = buffer[index]

            if byte == 0x1B {
                guard let consumed = consumeEscape(buffer, at: index, into: &keys) else {
                    pending = Array(buffer[index...]) // incomplete: wait for the rest
                    return keys
                }
                index += consumed
            } else if byte == 0x03 {
                // Always honoured, even mid-paste, so an unterminated paste can't trap you.
                keys.append(.ctrlC)
                index += 1
            } else {
                let end = min(index + Self.utf8Length(startingWith: byte), buffer.count)
                if !inPaste, byte >= 0x20, byte != 0x7F {
                    let text = String(decoding: buffer[index ..< end], as: UTF8.self)
                    if text.count == 1, let character = text.first, character != "\u{FFFD}" {
                        keys.append(.char(character))
                    }
                }
                index = end
            }
        }

        return keys
    }

    /// Returns how many bytes the escape sequence at `start` takes, or nil if it is incomplete.
    private mutating func consumeEscape(_ buffer: [UInt8], at start: Int, into keys: inout [Key]) -> Int? {
        guard start + 1 < buffer.count else { return nil }

        switch buffer[start + 1] {
        case 0x5B: // CSI
            return consumeCSI(buffer, at: start, into: &keys)
        case 0x4F: // SS3 (application-mode arrows)
            guard start + 2 < buffer.count else { return nil }
            if !inPaste {
                switch buffer[start + 2] {
                case 0x41: keys.append(.up)
                case 0x42: keys.append(.down)
                default: break
                }
            }
            return 3
        default:
            return 1 // a bare Esc (or Alt+key): drop the Esc, the next byte is read normally
        }
    }

    private mutating func consumeCSI(_ buffer: [UInt8], at start: Int, into keys: inout [Key]) -> Int? {
        var cursor = start + 2
        while cursor < buffer.count, (0x30 ... 0x3F).contains(buffer[cursor]) {
            cursor += 1
        } // parameters
        let parametersEnd = cursor
        while cursor < buffer.count, (0x20 ... 0x2F).contains(buffer[cursor]) {
            cursor += 1
        } // intermediates

        guard cursor < buffer.count else {
            return cursor - start > Self.maxSequenceLength ? 1 : nil
        }

        let final = buffer[cursor]
        let parameters = buffer[(start + 2) ..< parametersEnd]
        let consumed = cursor + 1 - start

        guard (0x40 ... 0x7E).contains(final) else { return consumed } // malformed: drop it

        switch (final, Array(parameters)) {
        case (0x7E, Array("200".utf8)):
            inPaste = true
        case (0x7E, Array("201".utf8)):
            inPaste = false
        case (0x41, []) where !inPaste:
            keys.append(.up)
        case (0x42, []) where !inPaste:
            keys.append(.down)
        default:
            break
        }
        return consumed
    }

    private static func utf8Length(startingWith byte: UInt8) -> Int {
        switch byte {
        case 0xF0...: 4
        case 0xE0...: 3
        case 0xC0...: 2
        default: 1
        }
    }
}
