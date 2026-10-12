import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const binPath = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'portwatch.js');

// React's development build records a performance.measure entry per component
// render, and Node never clears them, so a long-running portwatch grew past
// 1GB. bin/portwatch.js must therefore load React in production mode even
// when NODE_ENV isn't set (e.g. when launched from a Homebrew install).
// stdin isn't a TTY here, so Ink complains about raw mode, but it still
// renders first, which is all this needs.
test('portwatch loads React in production mode so render measures do not accumulate', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'portwatch-probe-'));
  const probe = path.join(dir, 'probe.mjs');
  writeFileSync(
    probe,
    `setTimeout(() => {
      process.stderr.write('MEASURES=' + performance.getEntriesByType('measure').length + '\\n');
      process.exit(0);
    }, 3000);`
  );

  const env = { ...process.env };
  delete env.NODE_ENV;
  const result = spawnSync(process.execPath, ['--import', probe, binPath], {
    env,
    stdio: ['ignore', 'ignore', 'pipe'],
    encoding: 'utf8',
  });

  const match = result.stderr.match(/MEASURES=(\d+)/);
  assert.ok(match, `probe did not report a measure count:\n${result.stderr}`);
  assert.equal(Number(match[1]), 0);
});
