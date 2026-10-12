# portwatch Swift rewrite: design spec

Date: 2026-10-12
Status: draft, supersedes the Node/Ink implementation in `2026-09-17-portwatch-design.md` once parity is reached

## Summary

Replace the Node/Ink implementation with a single dependency-free Swift binary that behaves identically from the user's side (same keys, columns, filtering, exclude file) but reads listening sockets, working directories and start times straight from libproc instead of spawning `lsof` and `ps` every 2 seconds. The motivation is install weight (no `node` formula), idle footprint, and removing the `lsof -F` parsing; it is not a correctness fix, since the 0.1.0 memory growth was a React build-mode bug already fixed in 0.1.1.

The hardest part is the data layer. Every libproc call, struct field and edge case in this spec is a hypothesis to verify against this machine before it is relied on (see "Verify before building").

## Scope

In scope (parity contract, taken from the current README and code):

- List every process with a listening TCP socket: process name, port, PID, source directory (cwd), uptime.
- Drop ports below 1024 and the hardcoded system-daemon list (`rapportd`, `ControlCenter`, `mDNSResponder`, `sharingd`, `identityservicesd`), unconditionally, not affected by show-all.
- Refresh every 2 seconds.
- Group a process holding several ports under one heading row with its ports indented beneath; single-port processes render as one full row. Groups sort by their lowest port.
- Rows are identified by `pid:port`. Selection survives refreshes and moves to the first row when the selected row disappears.
- Keys: `j`/`k` or arrows move (wrapping at both ends), `x` kill with `y`/`n` confirm (SIGTERM to the PID; a missing process counts as success), `e` toggle exclude by process name, `a` toggle show-all (excluded rows dimmed and tagged `(excluded)`), `q` or `Ctrl+C` quit.
- User excludes persist in `~/.config/portwatch/excludes.json` as a sorted JSON array of process names. The Swift version must read and write the existing file unchanged.
- PROCESS and PORT columns in the current order (PROCESS, PORT, PID, SOURCE, UPTIME), with SOURCE truncated from the front with a leading ellipsis.
- A lookup failure shows an error line and retries on the next tick; a process that exits mid-tick is dropped from that tick.
- `portwatch --version` prints the version.
- Installable via the existing `kaiyou-digital/tap` formula as `brew install portwatch`.

Out of scope (unchanged from v1): UDP, remote monitoring, SIGKILL escalation, history or alerting, Linux or Windows support.

## Architecture

SwiftPM package, no Xcode project (this is a CLI, so the XcodeGen setup from the SwiftUI apps does not apply):

```
Package.swift
Sources/
  PortwatchCore/        library, no I/O beyond the injected seams
    Service.swift         value types: Service, Group, Row
    ProcessSource.swift   protocol: listeningServices() -> [RawService]
    LibprocSource.swift   the only file that touches libproc
    Filters.swift         MIN_PORT + system-daemon list
    Grouping.swift        group-by-pid, sort, flatten to rows
    Uptime.swift          start time -> etime-style string
    ExcludeStore.swift    load/save excludes.json
    Kill.swift            SIGTERM with ESRCH treated as success
    AppState.swift        pure reducer: (state, event) -> state
    Render.swift          pure: (state, terminal size) -> [String] lines
  portwatch/            executable
    main.swift            arg handling, wiring
    Terminal.swift        termios raw mode, alt screen, key decoding, resize
Tests/
  PortwatchCoreTests/
```

The split mirrors the JS modules, so each existing unit test has a direct Swift counterpart. `AppState` and `Render` being pure is what makes the UI testable without a terminal; the existing Ink layer was never unit tested, and this is the main testing improvement available.

Uptime is formatted in the same shape `ps -o etime` produced (`[[dd-]hh:]mm:ss`) so the display does not change.

## Data collection

`LibprocSource` is the only code that calls libproc. Intended approach, per refresh tick:

1. `proc_listpids` to get all PIDs.
2. For each PID, `proc_pidinfo(PROC_PIDLISTFDS)` to list file descriptors, keeping socket fds.
3. For each socket fd, `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` and keep TCP sockets in the LISTEN state; read the local port (stored in network byte order).
4. For PIDs with at least one listener, read the working directory (`PROC_PIDVNODEPATHINFO`), the start time and the process name.
5. De-duplicate by `pid:port`, since a dual-stack listener appears once per address family (the JS parser does the same).

Cost shape: this touches every process on the machine each tick, where `lsof` was one call for sockets plus two batched calls. Expected to be cheap in-process but it is unmeasured; see risks.

Permissions: libproc will refuse fd and cwd queries for other users' processes without root. Expected result is that only the current user's processes appear, which is also the practical behaviour of `lsof` run unprivileged. A failed query on a single PID must skip that PID, never fail the tick.

The `ProcessSource` protocol is the test seam (same role as the injectable `exec` in `collectServices.js`). All non-libproc logic is tested with a fake source.

## Terminal layer

- Raw mode via `termios`, restored on every exit path: normal quit, `Ctrl+C`, SIGTERM, and a crash handler. A broken terminal after a crash is the worst failure mode of a hand-rolled TUI.
- Key decoding for `j k x e a q y n`, `Ctrl+C`, and the arrow-key escape sequences. Unknown sequences are ignored.
- SIGWINCH triggers a redraw; rendering clips to the terminal width and height.
- Rendering writes the full frame each tick and only when the frame differs from the last one.
- Colours and styles: bold header, inverse selected row, dim for excluded rows, yellow confirm prompt, red error line, as today.

## Quality gates

Follow the Kaiyou standard from the `app-quality-gates` skill: SwiftFormat and SwiftLint with pre-commit and pre-push hooks, `swift test` as the unit gate, manual-only CI. These tools are already installed on this machine.

## Testing

- Unit tests (against fixtures or a fake `ProcessSource`): filtering, grouping and ordering, uptime formatting for each etime shape, exclude file round-trip including the existing sorted-array format and a missing file, kill with ESRCH, the state reducer (selection wrap, selection recovery when a row disappears, confirm flow, show-all), and the renderer (column padding, front truncation, dim and tag for excluded rows).
- One parity check, run once by hand during migration: run the Node 0.1.1 build and the Swift build side by side and compare the rows they show. Differences are bugs in one or the other and must be explained before the JS is removed.
- No automated test touches real processes or a real terminal. The terminal layer is verified by running it.

## Distribution

- Release a prebuilt binary as a GitHub release asset; the tap formula installs it, with no `depends_on "node"` and no Xcode requirement for users.
- Keep a build-from-source path (`swift build -c release`) documented in the README.
- Open: arm64 only, or universal. This machine is arm64; no other target machine has been named.
- Open: whether to Developer ID sign and notarize. A binary fetched by Homebrew is not quarantined, so it likely runs without it, but confirm on a clean install.

## Migration

1. Add the Swift package alongside the JS; get the Swift tests green and the side-by-side parity check clean.
2. Switch the README, formula and `--version` to the Swift binary; release as the next minor version.
3. Remove `src/`, `bin/`, `test/`, `package.json` and `node_modules` handling from the repo in the same release or the one after.
4. Mark `2026-09-17-portwatch-design.md` as superseded.

## Verify before building

Each of these is currently an assumption, not a checked fact:

1. The libproc calls and struct fields above return what this spec says on this macOS version, including port byte order and the LISTEN state value.
2. How the process name should be derived. `lsof` produced the current names; libproc offers several name sources with different length limits, and the exclude list contains names longer than some of them. Compare against the Node build's output for every currently listed process.
3. Whether unprivileged libproc sees the same set of processes as the current `lsof` call, including anything owned by other users.
4. Per-tick cost of walking every PID versus the three `lsof`/`ps` calls, measured at idle.
5. Whether the current Ink UI draws inline or on the alternate screen, and which one to keep.
6. Swift 6 strict concurrency behaviour with a timer, a signal handler and an input reader sharing state.

## Risks

1. **Struct and API surprises in libproc.** The headers are sparse and the Swift imports are awkward. Mitigation: spike `LibprocSource` first, as a throwaway script that prints the same rows as the Node build, before writing anything else.
2. **Terminal left in raw mode after a crash.** Mitigation: a single restore function wired to every exit path, covered by a manual kill-the-process check.
3. **Silent parity drift** (names, ordering, uptime format). Mitigation: the side-by-side check is a gate for removing the JS, not a nice-to-have.

## Acceptance criteria

- Every item in the parity contract works in the Swift binary.
- An existing `~/.config/portwatch/excludes.json` is honoured and written back unchanged in format.
- `swift test` passes; formatting and lint gates pass.
- `brew install portwatch` from the tap installs the Swift binary without installing Node.
- Idle memory and per-tick CPU are measured and recorded in the README against the Node build.
