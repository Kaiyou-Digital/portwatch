import React from 'react';
import { Box, Text, useApp, useInput } from 'ink';
import { collectServices } from './collectServices.js';
import { killService } from './killService.js';
import { POLL_INTERVAL_MS } from './constants.js';

const h = React.createElement;

// A pid can hold more than one listening port (e.g. mysqld on 3306 and
// 33060), so pid alone isn't a unique row identity. Key/select rows by
// pid+port instead; kills still target the pid, since SIGTERM acts on
// the whole process, not a single port.
function rowKey(service) {
  return `${service.pid}:${service.port}`;
}

function pad(str, width) {
  if (str.length >= width) return str.slice(0, width - 1) + ' ';
  return str + ' '.repeat(width - str.length);
}

function HeaderRow() {
  return h(
    Box,
    null,
    h(Text, { bold: true }, pad('PORT', 8)),
    h(Text, { bold: true }, pad('PROCESS', 20)),
    h(Text, { bold: true }, pad('PID', 8)),
    h(Text, { bold: true }, pad('SOURCE', 44)),
    h(Text, { bold: true }, 'UPTIME')
  );
}

function ServiceRow({ service, selected }) {
  return h(
    Box,
    null,
    h(Text, { inverse: selected }, pad(String(service.port), 8)),
    h(Text, { inverse: selected }, pad(service.process, 20)),
    h(Text, { inverse: selected }, pad(String(service.pid), 8)),
    h(Text, { inverse: selected }, pad(service.source, 44)),
    h(Text, { inverse: selected }, service.uptime)
  );
}

export function App() {
  const { exit } = useApp();
  const [services, setServices] = React.useState([]);
  const [error, setError] = React.useState(null);
  const [selectedKey, setSelectedKey] = React.useState(null);
  const [confirmingKey, setConfirmingKey] = React.useState(null);

  React.useEffect(() => {
    let cancelled = false;

    async function tick() {
      try {
        const result = await collectServices();
        if (cancelled) return;
        setServices(result);
        setError(null);
        setSelectedKey((current) => {
          if (result.length === 0) return null;
          if (current !== null && result.some((s) => rowKey(s) === current)) return current;
          return rowKey(result[0]);
        });
      } catch (err) {
        if (!cancelled) setError(err.message);
      }
    }

    tick();
    const interval = setInterval(tick, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  useInput((input, key) => {
    if (confirmingKey !== null) {
      if (input === 'y') {
        const service = services.find((s) => rowKey(s) === confirmingKey);
        if (service) killService(service.pid);
      }
      setConfirmingKey(null);
      return;
    }

    if (input === 'q' || (key.ctrl && input === 'c')) {
      exit();
      return;
    }

    if (services.length === 0) return;
    const index = services.findIndex((s) => rowKey(s) === selectedKey);

    if (input === 'j' || key.downArrow) {
      const next = services[(index + 1 + services.length) % services.length];
      setSelectedKey(rowKey(next));
      return;
    }

    if (input === 'k' || key.upArrow) {
      const prev = services[(index - 1 + services.length) % services.length];
      setSelectedKey(rowKey(prev));
      return;
    }

    if (input === 'x' && selectedKey !== null) {
      setConfirmingKey(selectedKey);
    }
  });

  const confirmingService = services.find((s) => rowKey(s) === confirmingKey);

  return h(
    Box,
    { flexDirection: 'column' },
    h(HeaderRow),
    ...services.map((service) =>
      h(ServiceRow, { key: rowKey(service), service, selected: rowKey(service) === selectedKey })
    ),
    error ? h(Text, { color: 'red' }, `Error: ${error}`) : null,
    confirmingKey !== null && confirmingService
      ? h(
          Text,
          { color: 'yellow' },
          `Kill ${confirmingService.process} (PID ${confirmingService.pid})? y/n`
        )
      : h(Text, { dimColor: true }, 'j/k or arrows: move   x: kill   q: quit')
  );
}
