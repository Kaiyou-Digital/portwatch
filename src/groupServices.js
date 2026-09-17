// Precondition: `services` is already sorted by port ascending (as
// collectServices() guarantees), so each group's `ports` come out in
// ascending order for free — no per-group sort needed.
export function groupServices(services) {
  const groupsByPid = new Map();

  for (const service of services) {
    if (!groupsByPid.has(service.pid)) {
      groupsByPid.set(service.pid, {
        pid: service.pid,
        process: service.process,
        source: service.source,
        ports: [],
      });
    }
    groupsByPid.get(service.pid).ports.push({ port: service.port, uptime: service.uptime });
  }

  return [...groupsByPid.values()].sort((a, b) => a.ports[0].port - b.ports[0].port);
}
