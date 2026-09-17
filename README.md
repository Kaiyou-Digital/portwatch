# portwatch

A local TUI dashboard, built with [Ink](https://github.com/vadimdemedes/ink),
that lists every locally listening service on this machine — process name,
PID, port, source directory, and uptime — with a way to kill a service
straight from the list.

**Personal, single-machine tool.** No auth, no remote access.

## Prerequisites

- Node.js >= 22 (enforced via `package.json`'s `engines` field — Ink 7 requires it).
- macOS only. portwatch parses `lsof`'s `-F` field-output format and `ps -o comm=` output shape as-is, rather than abstracting them for other platforms.

## Install

```bash
npm install
npm link
```

This puts `portwatch` on your `PATH`.

## Run

```bash
portwatch
```

- `j`/`k` or arrow keys — move the selection
- `x` — kill the selected process (asks for `y`/`n` confirmation, sends `SIGTERM`)
- `e` — exclude (or un-exclude) the selected row's process, by name, from the list — persisted, so it stays excluded on future runs
- `a` — toggle showing excluded processes (dimmed, tagged `(excluded)`), so you can find one to un-exclude
- `q` / `Ctrl+C` — quit

The list auto-refreshes every 2 seconds. Ports below 1024 and a small list
of common macOS system daemons (see `src/constants.js`) are filtered out
unconditionally (not affected by `a`) to keep the list focused on dev
services — tune that list there if it's missing something on your machine.

A process holding more than one listening port (common — Dropbox, LM Studio,
Figma's desktop helper, and others often do) renders as one heading with its
ports as indented rows underneath, rather than as separate unrelated-looking
entries. Excluding via `e` applies to the whole process, not just one port.

Your own exclusions (via `e`) are stored separately from the hardcoded list
above, in `~/.config/portwatch/excludes.json`.

## Testing

```bash
npm test
```

Runs Node's built-in test runner over the parsers, filters, kill helper,
and service collector — all against fixture output or an injected fake
exec function. No automated test shells out to a real process.

## License

MIT © 2026 Andy Bennett — see [LICENSE](LICENSE).
