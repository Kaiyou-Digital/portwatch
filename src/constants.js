import { homedir } from 'node:os';
import path from 'node:path';

export const MIN_PORT = 1024;

export const EXCLUDES_FILE_PATH = path.join(homedir(), '.config', 'portwatch', 'excludes.json');

export const EXCLUDED_PROCESS_NAMES = [
  'rapportd',
  'ControlCenter',
  'mDNSResponder',
  'sharingd',
  'identityservicesd',
];

export const POLL_INTERVAL_MS = 2000;
