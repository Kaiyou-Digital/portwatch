#!/usr/bin/env python3
"""Smoke test: run the built binary in a pseudo-terminal and drive every input path.

Unit tests can't see runtime behaviour of the terminal layer: a main-actor
isolation warning, stray output over the TUI, or an unrestored terminal. Three
real bugs so far only appeared by running the binary, so this runs in the
pre-push gate.

Usage: Scripts/smoke.py <path-to-portwatch>
Needs no listening service of its own; whatever is listening on this machine is
shown, and the only destructive key sent (x) is cancelled with n.
"""
import fcntl
import os
import pty
import re
import select
import signal
import struct
import sys
import tempfile
import termios
import time

LEAVE = b"\x1b[?2004l\x1b[?25h\x1b[?1049l"
BAD_OUTPUT = re.compile(rb"data race|Fatal error|warning:|error:|Traceback", re.IGNORECASE)


class Session:
    def __init__(self, binary):
        self.out = b""
        home = tempfile.mkdtemp(prefix="pw-smoke-home-")
        pid, self.fd = pty.fork()
        if pid == 0:
            os.environ.update(HOME=home, TERM="xterm-256color")
            os.execv(binary, [binary])
        self.pid = pid
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 140, 0, 0))

    def drain(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([self.fd], [], [], 0.05)
            if ready:
                try:
                    self.out += os.read(self.fd, 65536)
                except OSError:
                    return

    def send(self, data, wait=0.5):
        os.write(self.fd, data)
        self.drain(wait)

    def resize(self, rows, cols):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        os.kill(self.pid, signal.SIGWINCH)
        self.drain(0.6)

    def finish(self):
        """Waits for the child to exit; returns its exit code (or None if it had to be killed)."""
        for _ in range(30):
            done, status = os.waitpid(self.pid, os.WNOHANG)
            if done:
                return os.waitstatus_to_exitcode(status)
            self.drain(0.1)
        os.kill(self.pid, signal.SIGKILL)
        os.waitpid(self.pid, 0)
        return None


failures = []


def check(name, condition, detail=""):
    print(("PASS " if condition else "FAIL ") + name + (f"  [{detail}]" if detail and not condition else ""))
    if not condition:
        failures.append(name)


def bad_lines(session):
    return [m.group(0)[:100].decode("utf8", "replace") for m in BAD_OUTPUT.finditer(session.out)][:3]


def main(binary):
    # 1. Every input path in one session: timer tick, keys, arrows, resize, then quit.
    s = Session(binary)
    s.drain(2.6)  # first draw plus the 2s poll timer
    s.send(b"j")
    s.send(b"k")
    s.send(b"\x1b[B")
    s.send(b"\x1b[A")
    s.send(b"x", 0.3)
    s.send(b"n")  # arm the kill prompt, then cancel it
    s.send(b"a")
    s.send(b"a")
    s.resize(40, 100)
    s.resize(20, 80)
    s.send(b"\x1b[200~xyxy\x1b[201~")  # bracketed paste
    s.send(b"q", 0.6)
    code = s.finish()
    check("no runtime warnings or errors in the output during keys, arrows, resize and paste", not bad_lines(s), "; ".join(bad_lines(s)))
    check("quit with q exits 0", code == 0, f"exit={code}")
    check("terminal restored after q", s.out.rstrip().endswith(LEAVE))

    # 2. Each signal exits cleanly and restores the terminal.
    for name in ("SIGINT", "SIGTERM", "SIGHUP"):
        s = Session(binary)
        s.drain(1.5)
        os.kill(s.pid, getattr(signal, name))
        s.drain(0.6)
        code = s.finish()
        check(f"{name} exits 0 with no warnings", code == 0 and not bad_lines(s), f"exit={code} {bad_lines(s)}")
        check(f"{name} restores the terminal", s.out.rstrip().endswith(LEAVE))

    # 3. Ctrl+C as a raw key.
    s = Session(binary)
    s.drain(1.5)
    s.send(b"\x03", 0.6)
    code = s.finish()
    check("raw Ctrl+C exits 0 and restores the terminal", code == 0 and s.out.rstrip().endswith(LEAVE), f"exit={code}")

    print("\nALL PASS" if not failures else f"\n{len(failures)} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: smoke.py <path-to-portwatch>")
    sys.exit(main(sys.argv[1]))
