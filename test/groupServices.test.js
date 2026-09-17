import { test } from 'node:test';
import assert from 'node:assert/strict';
import { groupServices } from '../src/groupServices.js';

test('groupServices puts a single-port process in its own one-port group', () => {
  const services = [{ port: 8934, process: 'node', pid: 63452, source: '/repo', uptime: '01:00:00' }];
  const result = groupServices(services);
  assert.deepEqual(result, [
    { pid: 63452, process: 'node', source: '/repo', ports: [{ port: 8934, uptime: '01:00:00' }] },
  ]);
});

test('groupServices collects multiple ports for the same pid into one group', () => {
  const services = [
    { port: 3306, process: 'mysqld', pid: 2210, source: '/opt/mysql', uptime: '03:00:00' },
    { port: 33060, process: 'mysqld', pid: 2210, source: '/opt/mysql', uptime: '03:00:00' },
  ];
  const result = groupServices(services);
  assert.deepEqual(result, [
    {
      pid: 2210,
      process: 'mysqld',
      source: '/opt/mysql',
      ports: [
        { port: 3306, uptime: '03:00:00' },
        { port: 33060, uptime: '03:00:00' },
      ],
    },
  ]);
});

test('groupServices orders groups by each group\'s lowest port, even when a pid\'s ports are not adjacent in the input', () => {
  const services = [
    { port: 100, process: 'alpha', pid: 1, source: '/a', uptime: '00:01' },
    { port: 200, process: 'beta', pid: 2, source: '/b', uptime: '00:02' },
    { port: 300, process: 'alpha', pid: 1, source: '/a', uptime: '00:01' },
  ];
  const result = groupServices(services);
  assert.deepEqual(
    result.map((g) => g.pid),
    [1, 2],
  );
  assert.deepEqual(
    result[0].ports.map((p) => p.port),
    [100, 300],
  );
});

test('groupServices returns an empty array for an empty input', () => {
  assert.deepEqual(groupServices([]), []);
});
