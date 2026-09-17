import React from 'react';
import { Box, Text, useApp, useInput } from 'ink';
import { collectServices } from './collectServices.js';
import { killService } from './killService.js';
import { groupServices } from './groupServices.js';
import { loadExcludes, saveExcludes } from './excludeStore.js';
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

// The SOURCE column holds filesystem paths, where the distinguishing part
// (e.g. the project directory name) is at the end, not the start. Truncating
// from the tail (like pad() does) can cut that off and even render two
// different deep paths identically if they share a long common prefix. This
// truncates from the front instead, keeping the tail, with a leading ellipsis
// to signal it's cut.
function padLeftTruncate(str, width) {
  if (str.length >= width) return '…' + str.slice(-(width - 2)) + ' ';
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

// Shown once above a multi-port process's rows, carrying the info that's
// common to all of them (process name, pid, source) so the rows underneath
// only need to show what differs (port, uptime).
function HeadingRow({ group, excluded }) {
  return h(
    Box,
    null,
    h(Text, { bold: true, dimColor: excluded }, pad('', 8)),
    h(Text, { bold: true, dimColor: excluded }, pad(group.process, 20)),
    h(Text, { bold: true, dimColor: excluded }, pad(String(group.pid), 8)),
    h(Text, { bold: true, dimColor: excluded }, padLeftTruncate(group.source, 44)),
    h(Text, { bold: true, dimColor: excluded }, excluded ? '(excluded)' : '')
  );
}

// A sub-row of a multi-port group (indent === true) only shows what
// differs from its sibling ports (port, uptime) — process/pid/source
// already appear once, on the HeadingRow above. A non-grouped, single-port
// row (indent === false) shows every column, as before grouping existed.
function ServiceRow({ service, selected, indent, excluded }) {
  const dim = excluded && !selected;
  const portText = (indent ? '  ' : '') + String(service.port);
  return h(
    Box,
    null,
    h(Text, { inverse: selected, dimColor: dim }, pad(portText, 8)),
    h(Text, { inverse: selected, dimColor: dim }, indent ? pad('', 20) : pad(service.process, 20)),
    h(Text, { inverse: selected, dimColor: dim }, indent ? pad('', 8) : pad(String(service.pid), 8)),
    h(
      Text,
      { inverse: selected, dimColor: dim },
      indent ? pad('', 44) : padLeftTruncate(service.source, 44)
    ),
    h(Text, { inverse: selected, dimColor: dim }, service.uptime)
  );
}

export function App() {
  const { exit } = useApp();
  const [services, setServices] = React.useState([]);
  const [error, setError] = React.useState(null);
  const [selectedKey, setSelectedKey] = React.useState(null);
  const [confirmingKey, setConfirmingKey] = React.useState(null);
  const [excludes, setExcludes] = React.useState(new Set());
  const [showAll, setShowAll] = React.useState(false);

  const visibleServices = showAll ? services : services.filter((s) => !excludes.has(s.process));
  const groups = groupServices(visibleServices);
  const flatRows = groups.flatMap((group) =>
    group.ports.map((p) => ({
      pid: group.pid,
      process: group.process,
      source: group.source,
      port: p.port,
      uptime: p.uptime,
    }))
  );

  // Loads the persisted exclude list before the first poll tick runs, so a
  // previously-excluded process never renders un-filtered for a frame while
  // collectServices() (a subprocess spawn) and loadExcludes() (a small file
  // read) race independently.
  React.useEffect(() => {
    let cancelled = false;
    let interval;

    async function tick() {
      try {
        const result = await collectServices();
        if (cancelled) return;
        setServices(result);
        setError(null);
      } catch (err) {
        if (!cancelled) setError(err.message);
      }
    }

    loadExcludes()
      .then((loaded) => {
        if (cancelled) return;
        setExcludes(loaded);
        tick();
        interval = setInterval(tick, POLL_INTERVAL_MS);
      })
      .catch((err) => {
        if (!cancelled) setError(err.message);
      });

    return () => {
      cancelled = true;
      if (interval) clearInterval(interval);
    };
  }, []);

  // Keeps the highlighted row valid whenever the visible row set changes —
  // a poll tick, an exclude/un-exclude, or toggling showAll can all make
  // the previously-selected row disappear (or, for the first render,
  // populate the list for the first time).
  React.useEffect(() => {
    setSelectedKey((current) => {
      if (flatRows.length === 0) return null;
      if (current !== null && flatRows.some((s) => rowKey(s) === current)) return current;
      return rowKey(flatRows[0]);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [services, excludes, showAll]);

  useInput((input, key) => {
    if (confirmingKey !== null) {
      if (input === 'y') {
        const service = flatRows.find((s) => rowKey(s) === confirmingKey);
        if (service) {
          const result = killService(service.pid);
          if (!result.ok) setError(`Kill failed: ${result.error.message}`);
        }
      }
      setConfirmingKey(null);
      return;
    }

    if (input === 'q' || (key.ctrl && input === 'c')) {
      exit();
      return;
    }

    if (input === 'a') {
      setShowAll((current) => !current);
      return;
    }

    if (flatRows.length === 0) return;
    const index = flatRows.findIndex((s) => rowKey(s) === selectedKey);

    if (input === 'j' || key.downArrow) {
      const next = flatRows[(index + 1 + flatRows.length) % flatRows.length];
      setSelectedKey(rowKey(next));
      return;
    }

    if (input === 'k' || key.upArrow) {
      const prev = flatRows[(index - 1 + flatRows.length) % flatRows.length];
      setSelectedKey(rowKey(prev));
      return;
    }

    if (input === 'x' && selectedKey !== null) {
      setConfirmingKey(selectedKey);
      return;
    }

    if (input === 'e' && selectedKey !== null) {
      const service = flatRows.find((s) => rowKey(s) === selectedKey);
      if (service) {
        const next = new Set(excludes);
        if (next.has(service.process)) next.delete(service.process);
        else next.add(service.process);
        setExcludes(next);
        saveExcludes(next).catch((err) => setError(`Failed to save exclude list: ${err.message}`));
      }
    }
  });

  const confirmingService = flatRows.find((s) => rowKey(s) === confirmingKey);

  const footerHint =
    'j/k or arrows: move   x: kill   e: exclude   a: show all   q: quit' +
    (showAll ? '  [showing excluded]' : '');

  return h(
    Box,
    { flexDirection: 'column' },
    h(HeaderRow),
    ...groups.flatMap((group) => {
      const isMultiPort = group.ports.length > 1;
      const groupExcluded = excludes.has(group.process);
      const rows = [];
      if (isMultiPort) {
        rows.push(h(HeadingRow, { key: `heading-${group.pid}`, group, excluded: groupExcluded }));
      }
      for (const p of group.ports) {
        const service = {
          pid: group.pid,
          process: group.process,
          source: group.source,
          port: p.port,
          uptime: p.uptime,
        };
        rows.push(
          h(ServiceRow, {
            key: rowKey(service),
            service,
            selected: rowKey(service) === selectedKey,
            indent: isMultiPort,
            excluded: groupExcluded,
          })
        );
      }
      return rows;
    }),
    error ? h(Text, { color: 'red' }, `Error: ${error}`) : null,
    confirmingKey !== null && confirmingService
      ? h(
          Text,
          { color: 'yellow' },
          `Kill ${confirmingService.process} (PID ${confirmingService.pid})? y/n`
        )
      : h(Text, { dimColor: true }, footerHint)
  );
}
