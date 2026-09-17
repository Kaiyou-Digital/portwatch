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
  'n/Users/andybennett/Work/Kaiyou/Apps/claude-cli-bridge',
].join('\n');

test('parseLsofCwds maps pid to cwd path', () => {
  const result = parseLsofCwds(CWD_FIXTURE);
  assert.deepEqual(result, {
    2210: '/opt/homebrew/var/mysql',
    63452: '/Users/andybennett/Work/Kaiyou/Apps/claude-cli-bridge',
  });
});

test('parseLsofCwds returns an empty object for empty output', () => {
  assert.deepEqual(parseLsofCwds(''), {});
});
