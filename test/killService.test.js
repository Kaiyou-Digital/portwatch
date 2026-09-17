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
