# portwatch

A local TUI dashboard, built with [Ink](https://github.com/vadimdemedes/ink),
that lists every locally listening service on this machine — process name,
PID, port, source directory, and uptime — with a way to kill a service
straight from the list.

**Personal, single-machine tool.** No auth, no remote access.

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
- `q` / `Ctrl+C` — quit

The list auto-refreshes every 2 seconds. Ports below 1024 and a small list
of common macOS system daemons (see `src/constants.js`) are filtered out
to keep the list focused on dev services — tune that list there if it's
missing something on your machine.

## Testing

```bash
npm test
```

Runs Node's built-in test runner over the parsers, filters, kill helper,
and service collector — all against fixture output or an injected fake
exec function. No automated test shells out to a real process.
