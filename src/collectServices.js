import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { parseLsofPorts, parseLsofCwds } from './parseLsof.js';
import { parsePs } from './parsePs.js';
import { filterServices } from './filters.js';

const execFileAsync = promisify(execFile);

export async function defaultExec(command, args) {
  try {
    const { stdout } = await execFileAsync(command, args, { maxBuffer: 10 * 1024 * 1024 });
    return stdout;
  } catch (err) {
    // A non-zero exit (e.g. lsof/ps exiting 1 because a queried pid died
    // mid-call) still gives usable partial stdout and a numeric err.code —
    // recover it. A spawn failure (e.g. ENOENT: the binary isn't on PATH)
    // also sets err.stdout to '', but gives a string err.code, so it must
    // still throw for the error state in App.js to be reachable.
    if (typeof err.code === 'number' && typeof err.stdout === 'string') return err.stdout;
    throw err;
  }
}

export async function collectServices(exec = defaultExec) {
  const portsOutput = await exec('lsof', ['-iTCP', '-sTCP:LISTEN', '-P', '-n', '-F', 'pcn']);
  const services = filterServices(parseLsofPorts(portsOutput));

  if (services.length === 0) return [];

  const pids = [...new Set(services.map((s) => s.pid))];
  const pidList = pids.join(',');

  const [cwdOutput, psOutput] = await Promise.all([
    exec('lsof', ['-p', pidList, '-a', '-d', 'cwd', '-F', 'pn']),
    exec('ps', ['-o', 'pid=,etime=,comm=', '-p', pidList]),
  ]);

  const cwdByPid = parseLsofCwds(cwdOutput);
  const etimeByPid = {};
  for (const record of parsePs(psOutput)) {
    etimeByPid[record.pid] = record.etime;
  }

  return services
    .filter((service) => cwdByPid[service.pid] !== undefined && etimeByPid[service.pid] !== undefined)
    .map((service) => ({
      port: service.port,
      process: service.command,
      pid: service.pid,
      source: cwdByPid[service.pid],
      uptime: etimeByPid[service.pid],
    }))
    .sort((a, b) => a.port - b.port);
}
