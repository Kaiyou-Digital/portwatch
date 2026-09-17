# portwatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `portwatch`, a local Ink TUI that lists every locally listening
service (port, process, PID, source directory, uptime), auto-refreshes, and
lets the user kill a selected service.

**Architecture:** Three batched shell-outs per refresh tick (`lsof` for
ports, `lsof` for cwd, `ps` for uptime) feed pure parser/filter functions
that produce a plain array of service records; an Ink root component polls
on an interval and renders that array as a table with keyboard navigation
and a kill-confirm flow.

**Tech Stack:** Node.js (>=22, native ESM, no build step), Ink 7, React 19,
Node's built-in test runner (`node --test`).

**Spec:** `docs/superpowers/specs/2026-09-17-portwatch-design.md`

## Global Constraints

- Node.js >= 22 (Ink 7 requires it; confirmed installed: v22.23.2).
- `package.json` must set `"type": "module"` — Ink 7 and React 19 ship ESM
  only, no CJS build. This means every relative import needs an explicit
  `.js` extension (Node ESM resolution requirement).
- Dependencies: `ink` (^7.1.1), `react` (^19.2.0). No other runtime
  dependencies — no JSX, no transpiler, no ink ecosystem add-ons (e.g. no
  `ink-table`).
- No automated tests shell out to a real process — `lsof`/`ps` calls are
  always reached through an injectable exec function in tests.
- `MIN_PORT = 1024`.
- `EXCLUDED_PROCESS_NAMES = ['rapportd', 'ControlCenter', 'mDNSResponder', 'sharingd', 'identityservicesd']`.
- `POLL_INTERVAL_MS = 2000`.
- Command name: `portwatch`, installed globally via `npm link`.

---

### Task 1: Project scaffold

**Files:**
- Create: `package.json`
- Create: `.gitignore`

**Interfaces:**
- Produces: an installable Node ESM project with `ink` and `react` in
  `node_modules`, a `test` script (`node --test`), and a `bin` field
  pointing at `bin/portwatch.js` (created in Task 7).

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "portwatch",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Local TUI dashboard for listening services, built with Ink",
  "bin": {
    "portwatch": "./bin/portwatch.js"
  },
  "engines": {
    "node": ">=22"
  },
  "scripts": {
    "test": "node --test"
  },
  "dependencies": {
    "ink": "^7.1.1",
    "react": "^19.2.0"
  }
}
```

- [ ] **Step 2: Write `.gitignore`**

```
node_modules/
```

- [ ] **Step 3: Install dependencies**

Run: `npm install`
Expected: completes without error; `node_modules/ink` and `node_modules/react`
exist; `package-lock.json` is created.

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json .gitignore
git commit -m "chore: scaffold portwatch project"
```

---

### Task 2: Constants and filters

**Files:**
- Create: `src/constants.js`
- Create: `src/filters.js`
- Test: `test/filters.test.js`

**Interfaces:**
- Produces: `MIN_PORT` (number), `EXCLUDED_PROCESS_NAMES` (string array),
  `POLL_INTERVAL_MS` (number) from `src/constants.js`.
- Produces: `filterServices(services)` from `src/filters.js`, where
  `services` is an array of `{ pid: number, command: string, port: number }`
  and the return value is the same shape, filtered.

- [ ] **Step 1: Write `src/constants.js`**

```js
export const MIN_PORT = 1024;

export const EXCLUDED_PROCESS_NAMES = [
  'rapportd',
  'ControlCenter',
  'mDNSResponder',
  'sharingd',
  'identityservicesd',
];

export const POLL_INTERVAL_MS = 2000;
```

- [ ] **Step 2: Write the failing test for `filterServices`**

```js
// test/filters.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { filterServices } from '../src/filters.js';

test('filterServices drops ports below MIN_PORT', () => {
  const services = [
    { pid: 1, command: 'devserver', port: 80 },
    { pid: 2, command: 'devserver', port: 3000 },
  ];
  const result = filterServices(services);
  assert.deepEqual(result, [{ pid: 2, command: 'devserver', port: 3000 }]);
});

test('filterServices drops excluded process names', () => {
  const services = [
    { pid: 1040, command: 'rapportd', port: 55898 },
    { pid: 1133, command: 'ControlCenter', port: 7000 },
    { pid: 63452, command: 'node', port: 8934 },
  ];
  const result = filterServices(services);
  assert.deepEqual(result, [{ pid: 63452, command: 'node', port: 8934 }]);
});

test('filterServices keeps services that pass both checks', () => {
  const services = [{ pid: 2210, command: 'mysqld', port: 33060 }];
  const result = filterServices(services);
  assert.deepEqual(result, services);
});

test('filterServices returns an empty array when given no services', () => {
  assert.deepEqual(filterServices([]), []);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `node --test test/filters.test.js`
Expected: FAIL — `filterServices` is not exported from `../src/filters.js`
(file doesn't exist yet).

- [ ] **Step 4: Write `src/filters.js`**

```js
import { MIN_PORT, EXCLUDED_PROCESS_NAMES } from './constants.js';

export function isFiltered(service) {
  if (service.port < MIN_PORT) return true;
  if (EXCLUDED_PROCESS_NAMES.includes(service.command)) return true;
  return false;
}

export function filterServices(services) {
  return services.filter((service) => !isFiltered(service));
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test test/filters.test.js`
Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add src/constants.js src/filters.js test/filters.test.js
git commit -m "feat: add port/process filtering"
```

---

### Task 3: Parse `lsof` output

**Files:**
- Create: `src/parseLsof.js`
- Test: `test/parseLsof.test.js`

**Interfaces:**
- Produces: `parseLsofPorts(output)` — takes the raw stdout string from
  `lsof -iTCP -sTCP:LISTEN -P -n -F pcn`, returns an array of
  `{ pid: number, command: string, port: number }`, deduplicated by
  `pid:port`.
- Produces: `extractPort(address)` — takes an address string like
  `*:55898` or `127.0.0.1:41343` or `[::1]:7679`, returns the port as a
  number, or `null` if unparseable.
- Produces: `parseLsofCwds(output)` — takes the raw stdout string from
  `lsof -p <pids> -a -d cwd -F pn`, returns an object mapping
  `pid (number) -> cwd path (string)`.

- [ ] **Step 1: Write the failing tests**

These fixtures are real captured output from this machine (`lsof -iTCP
-sTCP:LISTEN -P -n -F pcn` and `lsof -p <pids> -a -d cwd -F pn`), not
synthetic guesses — `lsof -F` output format is exact and easy to get subtly
wrong, so the tests are grounded in what the command actually prints.

```js
// test/parseLsof.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseLsofPorts, parseLsofCwds, extractPort } from '../src/parseLsof.js';

const PORTS_FIXTURE = [
  'p1040',
  'crapportd',
  'f10',
  'n*:55898',
  'f11',
  'n*:55898',
  'f20',
  'n*:65034',
  'f23',
  'n*:65035',
  'p1133',
  'cControlCenter',
  'f10',
  'n*:7000',
  'f11',
  'n*:7000',
  'f12',
  'n*:5000',
  'f13',
  'n*:5000',
  'p2210',
  'cmysqld',
  'f29',
  'n127.0.0.1:33060',
].join('\n');

test('parseLsofPorts dedupes repeated pid:port pairs and keeps distinct ports', () => {
  const result = parseLsofPorts(PORTS_FIXTURE);
  assert.deepEqual(result, [
    { pid: 1040, command: 'rapportd', port: 55898 },
    { pid: 1040, command: 'rapportd', port: 65034 },
    { pid: 1040, command: 'rapportd', port: 65035 },
    { pid: 1133, command: 'ControlCenter', port: 7000 },
    { pid: 1133, command: 'ControlCenter', port: 5000 },
    { pid: 2210, command: 'mysqld', port: 33060 },
  ]);
});

test('parseLsofPorts returns an empty array for empty output', () => {
  assert.deepEqual(parseLsofPorts(''), []);
});

test('extractPort parses wildcard, IPv4, and IPv6 addresses', () => {
  assert.equal(extractPort('*:55898'), 55898);
  assert.equal(extractPort('127.0.0.1:41343'), 41343);
  assert.equal(extractPort('[::1]:7679'), 7679);
});

test('extractPort returns null for an address with no port', () => {
  assert.equal(extractPort('no-colon-here'), null);
});

const CWD_FIXTURE = [
  'p2210',
  'fcwd',
  'n/opt/homebrew/var/mysql',
  'p63452',
  'fcwd',
  'n/Users/dev/projects/example-app',
].join('\n');

test('parseLsofCwds maps pid to cwd path', () => {
  const result = parseLsofCwds(CWD_FIXTURE);
  assert.deepEqual(result, {
    2210: '/opt/homebrew/var/mysql',
    63452: '/Users/dev/projects/example-app',
  });
});

test('parseLsofCwds returns an empty object for empty output', () => {
  assert.deepEqual(parseLsofCwds(''), {});
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test test/parseLsof.test.js`
Expected: FAIL — `../src/parseLsof.js` doesn't exist yet.

- [ ] **Step 3: Write `src/parseLsof.js`**

```js
export function extractPort(address) {
  const idx = address.lastIndexOf(':');
  if (idx === -1) return null;
  const portStr = address.slice(idx + 1);
  const port = Number(portStr);
  return Number.isInteger(port) ? port : null;
}

export function parseLsofPorts(output) {
  const lines = output.split('\n');
  const services = [];
  const seen = new Set();
  let pid = null;
  let command = null;

  for (const line of lines) {
    if (line.length === 0) continue;
    const tag = line[0];
    const value = line.slice(1);

    if (tag === 'p') {
      pid = Number(value);
      command = null;
    } else if (tag === 'c') {
      command = value;
    } else if (tag === 'n') {
      const port = extractPort(value);
      if (pid === null || command === null || port === null) continue;
      const key = `${pid}:${port}`;
      if (seen.has(key)) continue;
      seen.add(key);
      services.push({ pid, command, port });
    }
  }

  return services;
}

export function parseLsofCwds(output) {
  const lines = output.split('\n');
  const cwdByPid = {};
  let pid = null;

  for (const line of lines) {
    if (line.length === 0) continue;
    const tag = line[0];
    const value = line.slice(1);

    if (tag === 'p') {
      pid = Number(value);
    } else if (tag === 'n' && pid !== null) {
      cwdByPid[pid] = value;
    }
  }

  return cwdByPid;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test test/parseLsof.test.js`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add src/parseLsof.js test/parseLsof.test.js
git commit -m "feat: parse lsof -F output for ports and cwd"
```

---

### Task 4: Parse `ps` output

**Files:**
- Create: `src/parsePs.js`
- Test: `test/parsePs.test.js`

**Interfaces:**
- Produces: `parsePs(output)` — takes the raw stdout string from
  `ps -o pid=,etime=,comm= -p <pids>`, returns an array of
  `{ pid: number, etime: string, comm: string }`.

- [ ] **Step 1: Write the failing tests**

Fixture lines are real captured output from `ps -o pid=,etime=,comm= -p
<pids>` on this machine — note the right-justified `pid` field (variable
leading whitespace) and that `comm` can itself contain spaces (app names),
which is why the parser must not naively split on whitespace.

```js
// test/parsePs.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parsePs } from '../src/parsePs.js';

const PS_FIXTURE = [
  ' 1040 03-13:47:53 /usr/libexec/rapportd',
  '63452 01-01:01:21 node',
  '94938    07:08:16 /Applications/Dropbox.app/Contents/MacOS/Dropbox',
  '',
].join('\n');

test('parsePs extracts pid, etime, and comm (which may contain spaces)', () => {
  const result = parsePs(PS_FIXTURE);
  assert.deepEqual(result, [
    { pid: 1040, etime: '03-13:47:53', comm: '/usr/libexec/rapportd' },
    { pid: 63452, etime: '01-01:01:21', comm: 'node' },
    { pid: 94938, etime: '07:08:16', comm: '/Applications/Dropbox.app/Contents/MacOS/Dropbox' },
  ]);
});

test('parsePs skips blank lines', () => {
  assert.deepEqual(parsePs('\n\n'), []);
});

test('parsePs returns an empty array for empty output', () => {
  assert.deepEqual(parsePs(''), []);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test test/parsePs.test.js`
Expected: FAIL — `../src/parsePs.js` doesn't exist yet.

- [ ] **Step 3: Write `src/parsePs.js`**

```js
const PS_LINE_PATTERN = /^\s*(\d+)\s+(\S+)\s+(.*)$/;

export function parsePs(output) {
  const lines = output.split('\n');
  const records = [];

  for (const line of lines) {
    if (line.trim().length === 0) continue;
    const match = PS_LINE_PATTERN.exec(line);
    if (!match) continue;
    const [, pidStr, etime, comm] = match;
    records.push({ pid: Number(pidStr), etime, comm: comm.trim() });
  }

  return records;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test test/parsePs.test.js`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add src/parsePs.js test/parsePs.test.js
git commit -m "feat: parse ps output for pid/etime/comm"
```

---

### Task 5: Collect services

**Files:**
- Create: `src/collectServices.js`
- Test: `test/collectServices.test.js`

**Interfaces:**
- Consumes: `filterServices` from `./filters.js`, `parseLsofPorts` /
  `parseLsofCwds` from `./parseLsof.js`, `parsePs` from `./parsePs.js`.
- Produces: `collectServices(exec)` — `exec` is an async function
  `(command: string, args: string[]) => Promise<string>` (stdout), defaults
  to `defaultExec`. Returns a `Promise` resolving to an array of
  `{ port: number, process: string, pid: number, source: string, uptime: string }`,
  sorted by `port` ascending. Later tasks (App.js) render this array
  directly.
- Produces: `defaultExec(command, args)` — real `child_process.execFile`
  wrapper, exported for completeness but not unit tested (thin glue over a
  real shell-out; verified by manually running the app in Task 7).

- [ ] **Step 1: Write the failing tests**

```js
// test/collectServices.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { collectServices } from '../src/collectServices.js';

const PORTS_OUTPUT = [
  'p1040',
  'crapportd',
  'f10',
  'n*:55898',
  'p63452',
  'cnode',
  'f12',
  'n*:8934',
  'p99999',
  'cghost',
  'f8',
  'n*:9999',
].join('\n');

const CWD_OUTPUT = [
  'p63452',
  'fcwd',
  'n/Users/dev/projects/example-app',
  // no entry for pid 99999: simulates it exiting between the port scan
  // and the cwd lookup
].join('\n');

const PS_OUTPUT = [
  '63452 01-01:01:21 node',
  // no entry for pid 99999, same reasoning as above
].join('\n');

function makeFakeExec() {
  const calls = [];
  const exec = async (command, args) => {
    calls.push([command, args]);
    if (command === 'lsof' && args.includes('-sTCP:LISTEN')) return PORTS_OUTPUT;
    if (command === 'lsof' && args.includes('cwd')) return CWD_OUTPUT;
    if (command === 'ps') return PS_OUTPUT;
    throw new Error(`unexpected command: ${command} ${args.join(' ')}`);
  };
  return { exec, calls };
}

test('collectServices joins port/cwd/uptime data by pid, filters, and sorts by port', async () => {
  const { exec } = makeFakeExec();
  const result = await collectServices(exec);
  assert.deepEqual(result, [
    {
      port: 8934,
      process: 'node',
      pid: 63452,
      source: '/Users/dev/projects/example-app',
      uptime: '01-01:01:21',
    },
  ]);
});

test('collectServices excludes rapportd (system daemon) before doing cwd/ps lookups', async () => {
  const { exec, calls } = makeFakeExec();
  await collectServices(exec);
  const cwdCall = calls.find(([command, args]) => command === 'lsof' && args.includes('cwd'));
  assert.ok(!cwdCall[1].join(',').includes('1040'), 'pid 1040 (rapportd) should not be looked up');
});

test('collectServices drops a service that disappears before the cwd/ps lookups resolve', async () => {
  const { exec } = makeFakeExec();
  const result = await collectServices(exec);
  assert.ok(!result.some((s) => s.pid === 99999));
});

test('collectServices returns an empty array when no ports are listening', async () => {
  const exec = async () => '';
  const result = await collectServices(exec);
  assert.deepEqual(result, []);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test test/collectServices.test.js`
Expected: FAIL — `../src/collectServices.js` doesn't exist yet.

- [ ] **Step 3: Write `src/collectServices.js`**

```js
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { parseLsofPorts, parseLsofCwds } from './parseLsof.js';
import { parsePs } from './parsePs.js';
import { filterServices } from './filters.js';

const execFileAsync = promisify(execFile);

export async function defaultExec(command, args) {
  try {
    const { stdout } = await execFileAsync(command, args, { maxBuffer: 10 * 1024 * 1024 });
    return stdout;
  } catch (err) {
    if (typeof err.stdout === 'string') return err.stdout;
    throw err;
  }
}

export async function collectServices(exec = defaultExec) {
  const portsOutput = await exec('lsof', ['-iTCP', '-sTCP:LISTEN', '-P', '-n', '-F', 'pcn']);
  const services = filterServices(parseLsofPorts(portsOutput));

  if (services.length === 0) return [];

  const pids = [...new Set(services.map((s) => s.pid))];
  const pidList = pids.join(',');

  const [cwdOutput, psOutput] = await Promise.all([
    exec('lsof', ['-p', pidList, '-a', '-d', 'cwd', '-F', 'pn']),
    exec('ps', ['-o', 'pid=,etime=,comm=', '-p', pidList]),
  ]);

  const cwdByPid = parseLsofCwds(cwdOutput);
  const etimeByPid = {};
  for (const record of parsePs(psOutput)) {
    etimeByPid[record.pid] = record.etime;
  }

  return services
    .filter((service) => cwdByPid[service.pid] !== undefined && etimeByPid[service.pid] !== undefined)
    .map((service) => ({
      port: service.port,
      process: service.command,
      pid: service.pid,
      source: cwdByPid[service.pid],
      uptime: etimeByPid[service.pid],
    }))
    .sort((a, b) => a.port - b.port);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test test/collectServices.test.js`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add src/collectServices.js test/collectServices.test.js
git commit -m "feat: collect and join service data from lsof/ps"
```

---

### Task 6: Kill a service

**Files:**
- Create: `src/killService.js`
- Test: `test/killService.test.js`

**Interfaces:**
- Produces: `killService(pid, killFn)` — `killFn` is
  `(pid: number, signal: string) => void`, defaults to `process.kill`.
  Returns `{ ok: true }` on success or when the process is already gone
  (`ESRCH`), `{ ok: false, error: Error }` for any other failure.

- [ ] **Step 1: Write the failing tests**

```js
// test/killService.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { killService } from '../src/killService.js';

test('killService sends SIGTERM to the given pid', () => {
  const calls = [];
  const killFn = (pid, signal) => calls.push([pid, signal]);
  const result = killService(63452, killFn);
  assert.deepEqual(result, { ok: true });
  assert.deepEqual(calls, [[63452, 'SIGTERM']]);
});

test('killService treats an already-gone process (ESRCH) as success', () => {
  const killFn = () => {
    const err = new Error('No such process');
    err.code = 'ESRCH';
    throw err;
  };
  const result = killService(63452, killFn);
  assert.deepEqual(result, { ok: true });
});

test('killService reports failure for other errors', () => {
  const boom = new Error('Operation not permitted');
  boom.code = 'EPERM';
  const killFn = () => {
    throw boom;
  };
  const result = killService(63452, killFn);
  assert.equal(result.ok, false);
  assert.equal(result.error, boom);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test test/killService.test.js`
Expected: FAIL — `../src/killService.js` doesn't exist yet.

- [ ] **Step 3: Write `src/killService.js`**

```js
export function killService(pid, killFn = process.kill) {
  try {
    killFn(pid, 'SIGTERM');
    return { ok: true };
  } catch (err) {
    if (err && err.code === 'ESRCH') return { ok: true };
    return { ok: false, error: err };
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test test/killService.test.js`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add src/killService.js test/killService.test.js
git commit -m "feat: add process kill helper with ESRCH handling"
```

---

### Task 7: Ink UI, entry point, and README

**Files:**
- Create: `src/App.js`
- Create: `bin/portwatch.js`
- Create: `README.md`

**Interfaces:**
- Consumes: `collectServices` from `./collectServices.js`, `killService`
  from `./killService.js`, `POLL_INTERVAL_MS` from `./constants.js`.
- Produces: `App` (React component, named export) from `src/App.js`,
  rendered by `bin/portwatch.js`.

This task has no automated tests — it's the Ink rendering/interaction
layer, which the spec calls out as verified by actually running the tool
rather than unit tested. Verification is a manual run (Step 4).

- [ ] **Step 1: Write `src/App.js`**

```js
import React from 'react';
import { Box, Text, useApp, useInput } from 'ink';
import { collectServices } from './collectServices.js';
import { killService } from './killService.js';
import { POLL_INTERVAL_MS } from './constants.js';

const h = React.createElement;

function pad(str, width) {
  if (str.length >= width) return str.slice(0, width - 1) + ' ';
  return str + ' '.repeat(width - str.length);
}

function HeaderRow() {
  return h(
    Box,
    null,
    h(Text, { bold: true }, pad('PORT', 8)),
    h(Text, { bold: true }, pad('PROCESS', 20)),
    h(Text, { bold: true }, pad('PID', 8)),
    h(Text, { bold: true }, pad('SOURCE', 44)),
    h(Text, { bold: true }, 'UPTIME')
  );
}

function ServiceRow({ service, selected }) {
  return h(
    Box,
    null,
    h(Text, { inverse: selected }, pad(String(service.port), 8)),
    h(Text, { inverse: selected }, pad(service.process, 20)),
    h(Text, { inverse: selected }, pad(String(service.pid), 8)),
    h(Text, { inverse: selected }, pad(service.source, 44)),
    h(Text, { inverse: selected }, service.uptime)
  );
}

export function App() {
  const { exit } = useApp();
  const [services, setServices] = React.useState([]);
  const [error, setError] = React.useState(null);
  const [selectedPid, setSelectedPid] = React.useState(null);
  const [confirmingPid, setConfirmingPid] = React.useState(null);

  React.useEffect(() => {
    let cancelled = false;

    async function tick() {
      try {
        const result = await collectServices();
        if (cancelled) return;
        setServices(result);
        setError(null);
        setSelectedPid((current) => {
          if (result.length === 0) return null;
          if (current !== null && result.some((s) => s.pid === current)) return current;
          return result[0].pid;
        });
      } catch (err) {
        if (!cancelled) setError(err.message);
      }
    }

    tick();
    const interval = setInterval(tick, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  useInput((input, key) => {
    if (confirmingPid !== null) {
      if (input === 'y') killService(confirmingPid);
      setConfirmingPid(null);
      return;
    }

    if (input === 'q' || (key.ctrl && input === 'c')) {
      exit();
      return;
    }

    if (services.length === 0) return;
    const index = services.findIndex((s) => s.pid === selectedPid);

    if (input === 'j' || key.downArrow) {
      const next = services[(index + 1 + services.length) % services.length];
      setSelectedPid(next.pid);
      return;
    }

    if (input === 'k' || key.upArrow) {
      const prev = services[(index - 1 + services.length) % services.length];
      setSelectedPid(prev.pid);
      return;
    }

    if (input === 'x' && selectedPid !== null) {
      setConfirmingPid(selectedPid);
    }
  });

  const confirmingService = services.find((s) => s.pid === confirmingPid);

  return h(
    Box,
    { flexDirection: 'column' },
    h(HeaderRow),
    ...services.map((service) =>
      h(ServiceRow, { key: service.pid, service, selected: service.pid === selectedPid })
    ),
    error ? h(Text, { color: 'red' }, `Error: ${error}`) : null,
    confirmingPid !== null && confirmingService
      ? h(
          Text,
          { color: 'yellow' },
          `Kill ${confirmingService.process} (PID ${confirmingService.pid})? y/n`
        )
      : h(Text, { dimColor: true }, 'j/k or arrows: move   x: kill   q: quit')
  );
}
```

- [ ] **Step 2: Write `bin/portwatch.js`**

```js
#!/usr/bin/env node
import React from 'react';
import { render } from 'ink';
import { App } from '../src/App.js';

render(React.createElement(App));
```

Make it executable:

Run: `chmod +x bin/portwatch.js`

- [ ] **Step 3: Write `README.md`**

```markdown
# portwatch

A local TUI dashboard, built with [Ink](https://github.com/vadimdemedes/ink),
that lists every locally listening service on this machine — process name,
PID, port, source directory, and uptime — with a way to kill a service
straight from the list.

**Personal, single-machine tool.** No auth, no remote access.

## Install

\`\`\`bash
npm install
npm link
\`\`\`

This puts `portwatch` on your `PATH`.

## Run

\`\`\`bash
portwatch
\`\`\`

- `j`/`k` or arrow keys — move the selection
- `x` — kill the selected process (asks for `y`/`n` confirmation, sends `SIGTERM`)
- `q` / `Ctrl+C` — quit

The list auto-refreshes every 2 seconds. Ports below 1024 and a small list
of common macOS system daemons (see `src/constants.js`) are filtered out
to keep the list focused on dev services — tune that list there if it's
missing something on your machine.

## Testing

\`\`\`bash
npm test
\`\`\`

Runs Node's built-in test runner over the parsers, filters, kill helper,
and service collector — all against fixture output or an injected fake
exec function. No automated test shells out to a real process.
```

- [ ] **Step 4: Run the full test suite, then link and manually verify**

Run: `npm test`
Expected: PASS, all tests from Tasks 2–6.

Run: `npm link`
Expected: completes without error; `which portwatch` resolves to the linked
binary.

Run: `portwatch`
Expected: a table appears listing this machine's real listening services
(e.g. `claude-cli-bridge` on port 8934 with its actual source directory),
`j`/`k`/arrows move the highlighted row, `x` then `y` on a disposable
service kills it and the row disappears on the next refresh, `q` quits
cleanly back to the shell.

- [ ] **Step 5: Commit**

```bash
git add src/App.js bin/portwatch.js README.md
git commit -m "feat: add Ink UI, CLI entry point, and README"
```
