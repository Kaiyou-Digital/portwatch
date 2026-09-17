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
