# portwatch — design spec

Date: 2026-09-17

## Purpose

A local TUI dashboard, built with Ink (React for CLIs), that lists every
locally listening service on the machine — process name, PID, port, source
directory (cwd), and uptime — with a way to kill a service from the list.
Motivated by losing track of long-running dev services like `claude-cli-bridge`
(discovered running for 1 day+ without realizing it), and no existing TUI
combines "listening service" with "where it's running from."

This is a **personal, single-machine developer tool**. No auth, no remote
access, no packaging for distribution beyond the author's own machine.

## Scope

**In scope:**
- Detect every process with an open listening TCP socket on localhost.
- Show: port, process name, PID, source directory (cwd), uptime.
- Filter out low ports (<1024) and a hardcoded list of common macOS system
  daemons, so the list stays focused on dev/user services.
- Auto-refresh the list every 2 seconds.
- Let the user select a row and kill that process (SIGTERM, with a y/n
  confirm step).
- Install as a global command (`portwatch`) via `npm link`.

**Out of scope (v1):**
- UDP sockets, non-TCP services.
- Remote/multi-machine monitoring.
- SIGKILL escalation if SIGTERM doesn't work (re-run and retry instead).
- Historical logging, alerting, or persistence between runs.
- A configurable watchlist for non-port-bound background processes.

## Architecture

```
bin/portwatch.js        shebang entry point; calls ink's render(App)
src/App.js              root Ink component: polling loop, selection state,
                         renders Table + Footer, handles useInput for
                         navigation, kill-confirm, and quit
src/collectServices.js  orchestrates the 3 shell-outs per refresh tick,
                         returns a parsed, filtered, sorted array of services
src/parseLsof.js        pure parser: lsof -F output -> structured records
src/parsePs.js          pure parser: ps output -> structured records
src/filters.js          low-port + exclude-list filtering logic
src/constants.js        EXCLUDED_PROCESS_NAMES, MIN_PORT, POLL_INTERVAL_MS
test/                   node --test unit tests (parsers, filters, collector)
README.md               install/run instructions
package.json            bin: { "portwatch": "./bin/portwatch.js" }
```

No JSX, no build step. Ink components are written with `React.createElement`
directly so `bin/portwatch.js` runs under plain Node with zero transpilation.
If the component tree grows enough that this gets unwieldy, JSX + a runtime
loader (e.g. `tsx`) is a straightforward future upgrade — not needed for v1's
component count (root app, table, footer).

## Data collection (per refresh tick)

Three shell-outs, regardless of how many services are running:

1. `lsof -iTCP -sTCP:LISTEN -P -n -F pcn` — every listening PID + port in one
   call. `-F` gives machine-readable field output (`parseLsof.js` parses it).
2. Collect the unique PIDs from step 1, then one batched call:
   `lsof -p <pid1,pid2,...> -a -d cwd -F pn` — cwd for all of them together,
   not one lsof call per process. The `p` field is required alongside `n`
   even though only the cwd path is used downstream — without it there's no
   way to map each returned cwd back to the pid it belongs to.
3. One batched call: `ps -o pid=,etime=,comm= -p <pid1,pid2,...>` — uptime
   and command name for all of them together.

`collectServices.js` takes an injectable exec function (same pattern as
claude-cli-bridge's `claudeCli.js`), so it's testable without shelling out
for real. It joins the three results by PID, applies filtering
(`filters.js`), sorts by port ascending, and returns the array `App.js`
renders.

## Filtering

- Drop any service on a port < 1024 (`MIN_PORT` in `constants.js`).
- Drop any service whose process name matches `EXCLUDED_PROCESS_NAMES`, a
  hardcoded array in `constants.js` covering common macOS system daemons
  (`rapportd`, `ControlCenter`, `mDNSResponder`, `sharingd`,
  `identityservicesd`, and similar). This list is expected to need manual
  tuning after first real use — it lives in one file specifically so that's
  a one-line edit, not a logic change.

## UI / interaction

**Layout:** a fixed-width table rendered with Ink's `Box`/`Text` primitives.
Columns: `PORT | PROCESS | PID | SOURCE | UPTIME`. Header row bolded. One row
per service.

**Refresh:** `useEffect` + `setInterval`, default 2000ms
(`POLL_INTERVAL_MS`), re-running `collectServices` and replacing state.
Row selection is tracked by PID, not row index, so the highlighted row
doesn't jump if list order shifts between ticks.

**Navigation:** arrow keys or `j`/`k` move the highlighted-row cursor via
Ink's `useInput`.

**Kill flow:** pressing `x` on a highlighted row arms a confirm state,
shown in a footer bar: `Kill <process> (PID <pid>)? y/n`. Pressing `y`
sends `SIGTERM` to that PID; any other key cancels and returns to normal
navigation. No SIGKILL escalation — if the process doesn't die, the user
re-runs and tries again.

**Quit:** `q` or `Ctrl+C`.

## Error handling

- If `lsof`/`ps` aren't found or a shell-out fails outright, show an error
  state in the table area instead of crashing, and keep retrying on the next
  poll tick.
- A process that disappears between the port-scan and the cwd/ps lookups
  (exits mid-tick) is simply dropped from that tick's results rather than
  erroring the whole refresh.
- A `kill` call on a PID that's already gone is treated as success (nothing
  to confirm afterward — the process is gone either way).

## Testing

Mirrors claude-cli-bridge's approach:
- `parseLsof.js`, `parsePs.js`, `filters.js` — unit tested against fixture
  output strings (real `lsof -F`/`ps` output shapes, edge cases like empty
  results, malformed lines).
- `collectServices.js` — tested with an injected fake exec function; no real
  shell-outs in the test suite.
- Ink's rendering layer (`App.js`) is not unit tested — low value to test a
  UI shell in isolation. Verified instead by actually running the TUI once
  built.
- `npm test` runs Node's built-in test runner (`node --test`), no external
  test framework dependency, consistent with claude-cli-bridge.

## Distribution

- `npm init`, `bin` field pointing at `bin/portwatch.js`.
- `npm link` to install the `portwatch` command globally.
- README documents install/run, mirroring claude-cli-bridge's and
  remarka's README structure.

## Open questions / risks

- The `EXCLUDED_PROCESS_NAMES` list is a best guess and will likely need
  real-world tuning after first use on this machine.
- `lsof -F` field parsing needs to handle the actual output format
  correctly — verified during implementation against real `lsof` output on
  this machine, not just assumed from documentation.
