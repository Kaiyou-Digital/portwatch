import Darwin

// The terminal must be restored on every exit path, including crashes: a
// terminal left in raw mode on the alternate screen is unusable. These are
// globals so the restore function can be called from a signal handler.
private nonisolated(unsafe) var originalTermios = termios()
private nonisolated(unsafe) var terminalIsRaw = false

// Bracketed paste (2004) makes the terminal wrap pasted text in markers so it can be told apart from typing.
private let enterSequence = "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h"
private let leaveSequence = "\u{1B}[?2004l\u{1B}[?25h\u{1B}[?1049l"

/// Best-effort and safe to call from a signal handler (only tcsetattr and write).
func restoreTerminal() {
    guard terminalIsRaw else { return }
    terminalIsRaw = false
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    _ = leaveSequence.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
}

func enterRawMode() {
    tcgetattr(STDIN_FILENO, &originalTermios)
    var raw = originalTermios
    cfmakeraw(&raw)
    raw.c_oflag |= tcflag_t(OPOST) // keep "\n" -> "\r\n" translation on output
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    terminalIsRaw = true
    _ = enterSequence.withCString { write(STDOUT_FILENO, $0, strlen($0)) }

    for fatal in [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE] {
        signal(fatal) { number in
            restoreTerminal()
            signal(number, SIG_DFL)
            raise(number)
        }
    }
}

func terminalSize() -> (width: Int, height: Int) {
    var size = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 {
        return (Int(size.ws_col), Int(size.ws_row))
    }
    return (80, 24)
}

func writeOut(_ text: String) {
    var remaining = Array(text.utf8)[...]
    while !remaining.isEmpty {
        let written = remaining.withUnsafeBytes { write(STDOUT_FILENO, $0.baseAddress, $0.count) }
        if written <= 0 {
            return
        }
        remaining = remaining.dropFirst(written)
    }
}
