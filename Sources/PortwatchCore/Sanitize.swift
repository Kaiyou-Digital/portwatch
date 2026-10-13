/// Process names and working directories come from other processes (and, for
/// directories, can come from a cloned repo's folder names), so they can
/// contain anything, including terminal escape sequences. Written to the
/// terminal verbatim those can retitle the window, move the cursor to spoof or
/// hide rows, or on some terminals write to the clipboard.
///
/// Every scalar that could act as a control is replaced 1:1 with U+FFFD, so
/// column alignment is unchanged and nothing hostile reaches the terminal.
public enum Sanitize {
    public static let replacement: Unicode.Scalar = "\u{FFFD}"

    public static func displayText(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            scalars.append(isUnsafe(scalar) ? replacement : scalar)
        }
        return String(scalars)
    }

    private static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator:
            // C0 (including ESC), DEL, C1 (including the single-byte CSI U+009B), U+2028/U+2029.
            return true
        default:
            break
        }
        switch scalar.value {
        case 0x061C, 0x200E, 0x200F, 0x202A ... 0x202E, 0x2066 ... 0x2069:
            // Bidirectional formatting controls can reorder text to spoof what is on screen.
            return true
        default:
            return false
        }
    }
}
