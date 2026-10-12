# portwatch

A local TUI dashboard, written in Swift with no dependencies, that lists every
locally listening service on this machine — process name, PID, port, source
directory, and uptime — with a way to kill a service straight from the list.

**Personal, single-machine tool.** No auth, no remote access.

## Prerequisites

- macOS 13 or later. portwatch reads listening sockets through libproc (the same source `lsof` uses), which is macOS-specific, so there is no Linux or Windows support.
- Building from source needs a Swift 6 toolchain (Xcode or the Command Line Tools). The Homebrew install needs neither Swift nor Node.

## Install

Via Homebrew:

```bash
brew tap kaiyou-digital/tap
brew install portwatch
```

Or from source:

```bash
swift build -c release
cp .build/release/portwatch /usr/local/bin/   # or anywhere on your PATH
```

## Run

```bash
portwatch
```

- `j`/`k` or arrow keys — move the selection
- `x` — kill the selected process (asks for `y`/`n` confirmation, sends `SIGTERM`)
- `e` — exclude (or un-exclude) the selected row's process, by name, from the list — persisted, so it stays excluded on future runs
- `a` — toggle showing excluded processes (dimmed, tagged `(excluded)`), so you can find one to un-exclude
- `q` / `Ctrl+C` — quit

portwatch draws on the terminal's alternate screen, so quitting leaves your scrollback as it was.

The list auto-refreshes every 2 seconds. Ports below 1024 and a small list
of common macOS system daemons (see `Sources/PortwatchCore/Filters.swift`) are filtered out
unconditionally (not affected by `a`) to keep the list focused on dev
services — tune that list there if it's missing something on your machine.

A process holding more than one listening port (common — Dropbox, LM Studio,
Figma's desktop helper, and others often do) renders as one heading with its
ports as indented rows underneath, rather than as separate unrelated-looking
entries. Excluding via `e` applies to the whole process, not just one port.

Your own exclusions (via `e`) are stored separately from the hardcoded list
above, in `~/.config/portwatch/excludes.json` (under `$HOME`, if set). The file format is a sorted JSON array of process names, unchanged from the Node version, so an existing file keeps working.

Only processes owned by your own user are listed, since libproc won't report on other users' processes without root. Unprivileged `lsof` behaves the same way.

## Testing

```bash
swift test
```

Covers filtering, grouping, uptime formatting, the exclude file, the kill
helper, key decoding, the state reducer and the renderer, all against fake
data. Nothing in the automated suite reads real processes or touches a
terminal: `LibprocSource` and the terminal layer are verified by running the
binary.

### Git hooks

```bash
Scripts/install-git-hooks.sh
```

`pre-commit` formats staged files, blocks on lint errors and runs the tests.
`pre-push` is the full gate: format check, strict lint, and tests in Debug and
Release. Bypass it once with `SKIP_PREPUSH=1 git push`. CI
(`.github/workflows/swift-ci.yml`) is manual-only and runs the same checks.

## Footprint

Measured once on an arm64 Mac (macOS 27, Swift 6.4, Node 22), idle for 30 seconds
in a terminal:

| | Swift | Node (0.1.1) |
|---|---|---|
| Resident memory | 6.8 MB | 41.4 MB |
| CPU time | 0.06 s | 0.43 s |

The Node figure covers the Node process only, not the `lsof` and `ps` children it spawned every 2 seconds.

## License

MIT © 2026 Andy Bennett — see [LICENSE](LICENSE).
