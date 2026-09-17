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
  'n/Users/andybennett/Work/Kaiyou/Apps/claude-cli-bridge',
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
      source: '/Users/andybennett/Work/Kaiyou/Apps/claude-cli-bridge',
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
