public enum KeyDecoder {
    /// Decodes a chunk of raw terminal input. Handles several keys arriving in
    /// one read, arrow-key escape sequences (CSI and SS3 forms) and UTF-8
    /// text; anything unrecognised is dropped.
    public static func decode(_ bytes: [UInt8]) -> [Key] {
        var keys: [Key] = []
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]

            if byte == 0x1B {
                if index + 2 < bytes.count, bytes[index + 1] == 0x5B || bytes[index + 1] == 0x4F {
                    switch bytes[index + 2] {
                    case 0x41: keys.append(.up)
                    case 0x42: keys.append(.down)
                    default: break
                    }
                    index += 3
                } else {
                    index += 1
                }
                continue
            }

            if byte == 0x03 {
                keys.append(.ctrlC)
                index += 1
                continue
            }

            // Take the rest of this UTF-8 scalar.
            let length = byte < 0x80 ? 1 : byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
            let end = min(index + length, bytes.count)
            let text = String(decoding: bytes[index ..< end], as: UTF8.self)
            if byte >= 0x20, byte != 0x7F, text.count == 1, let character = text.first, character != "\u{FFFD}" {
                keys.append(.char(character))
            }
            index = end
        }

        return keys
    }
}
