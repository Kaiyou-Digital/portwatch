import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { EXCLUDES_FILE_PATH } from './constants.js';

export async function loadExcludes(filePath = EXCLUDES_FILE_PATH) {
  try {
    const content = await readFile(filePath, 'utf8');
    return new Set(JSON.parse(content));
  } catch (err) {
    if (err.code === 'ENOENT') return new Set();
    throw err;
  }
}

export async function saveExcludes(names, filePath = EXCLUDES_FILE_PATH) {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, JSON.stringify([...names].sort(), null, 2));
}
