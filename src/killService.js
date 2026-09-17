export function killService(pid, killFn = process.kill) {
  try {
    killFn(pid, 'SIGTERM');
    return { ok: true };
  } catch (err) {
    if (err && err.code === 'ESRCH') return { ok: true };
    return { ok: false, error: err };
  }
}
