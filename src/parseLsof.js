export function extractPort(address) {
  const idx = address.lastIndexOf(':');
  if (idx === -1) return null;
  const portStr = address.slice(idx + 1);
  if (portStr.length === 0) return null;
  const port = Number(portStr);
  return Number.isInteger(port) ? port : null;
}

export function parseLsofPorts(output) {
  const lines = output.split('\n');
  const services = [];
  const seen = new Set();
  let pid = null;
  let command = null;

  for (const line of lines) {
    if (line.length === 0) continue;
    const tag = line[0];
    const value = line.slice(1);

    if (tag === 'p') {
      pid = Number(value);
      command = null;
    } else if (tag === 'c') {
      command = value;
    } else if (tag === 'n') {
      const port = extractPort(value);
      if (pid === null || command === null || port === null) continue;
      const key = `${pid}:${port}`;
      if (seen.has(key)) continue;
      seen.add(key);
      services.push({ pid, command, port });
    }
  }

  return services;
}

export function parseLsofCwds(output) {
  const lines = output.split('\n');
  const cwdByPid = {};
  let pid = null;

  for (const line of lines) {
    if (line.length === 0) continue;
    const tag = line[0];
    const value = line.slice(1);

    if (tag === 'p') {
      pid = Number(value);
    } else if (tag === 'n' && pid !== null) {
      cwdByPid[pid] = value;
    }
  }

  return cwdByPid;
}
