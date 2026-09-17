import { test } from 'node:test';
import assert from 'node:assert/strict';
import { filterServices } from '../src/filters.js';

test('filterServices drops ports below MIN_PORT', () => {
  const services = [
    { pid: 1, command: 'devserver', port: 80 },
    { pid: 2, command: 'devserver', port: 3000 },
  ];
  const result = filterServices(services);
  assert.deepEqual(result, [{ pid: 2, command: 'devserver', port: 3000 }]);
});

test('filterServices drops excluded process names', () => {
  const services = [
    { pid: 1040, command: 'rapportd', port: 55898 },
    { pid: 1133, command: 'ControlCenter', port: 7000 },
    { pid: 63452, command: 'node', port: 8934 },
  ];
  const result = filterServices(services);
  assert.deepEqual(result, [{ pid: 63452, command: 'node', port: 8934 }]);
});

test('filterServices keeps services that pass both checks', () => {
  const services = [{ pid: 2210, command: 'mysqld', port: 33060 }];
  const result = filterServices(services);
  assert.deepEqual(result, services);
});

test('filterServices returns an empty array when given no services', () => {
  assert.deepEqual(filterServices([]), []);
});
