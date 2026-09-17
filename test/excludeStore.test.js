import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { loadExcludes, saveExcludes } from '../src/excludeStore.js';

async function withTempDir(fn) {
  const dir = await mkdtemp(path.join(tmpdir(), 'portwatch-test-'));
  try {
    await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

test('loadExcludes returns an empty set when the file does not exist yet', async () => {
  await withTempDir(async (dir) => {
    const filePath = path.join(dir, 'excludes.json');
    const result = await loadExcludes(filePath);
    assert.deepEqual(result, new Set());
  });
});

test('saveExcludes then loadExcludes round-trips the same set of names', async () => {
  await withTempDir(async (dir) => {
    const filePath = path.join(dir, 'excludes.json');
    await saveExcludes(new Set(['Dropbox', 'figma_agent']), filePath);
    const result = await loadExcludes(filePath);
    assert.deepEqual(result, new Set(['Dropbox', 'figma_agent']));
  });
});

test('saveExcludes creates the parent directory if it does not exist yet', async () => {
  await withTempDir(async (dir) => {
    const filePath = path.join(dir, 'nested', 'config', 'excludes.json');
    await saveExcludes(new Set(['mysqld']), filePath);
    const result = await loadExcludes(filePath);
    assert.deepEqual(result, new Set(['mysqld']));
  });
});
