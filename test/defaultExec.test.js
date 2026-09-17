import { test } from 'node:test';
import assert from 'node:assert/strict';
import { defaultExec } from '../src/collectServices.js';

// defaultExec has no injectable exec seam (it wraps execFile directly), so
// these shell out for real rather than using a fake. Both cases are
// deterministic on any POSIX system: `sh` is always present, and the
// bogus binary name is guaranteed not to exist on PATH.

test('defaultExec recovers partial stdout from a non-zero exit (numeric err.code)', async () => {
  const stdout = await defaultExec('sh', ['-c', 'echo hello; exit 1']);
  assert.equal(stdout, 'hello\n');
});

test('defaultExec throws on a spawn failure (string err.code, e.g. ENOENT) instead of swallowing it', async () => {
  await assert.rejects(
    () => defaultExec('portwatch-nonexistent-binary-xyz', []),
    (err) => {
      assert.equal(typeof err.code, 'string');
      return true;
    }
  );
});
