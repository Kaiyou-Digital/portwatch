const PS_LINE_PATTERN = /^\s*(\d+)\s+(\S+)\s+(.*)$/;

export function parsePs(output) {
  const lines = output.split('\n');
  const records = [];

  for (const line of lines) {
    if (line.trim().length === 0) continue;
    const match = PS_LINE_PATTERN.exec(line);
    if (!match) continue;
    const [, pidStr, etime, comm] = match;
    records.push({ pid: Number(pidStr), etime, comm: comm.trim() });
  }

  return records;
}
