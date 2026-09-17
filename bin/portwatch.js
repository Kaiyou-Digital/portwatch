#!/usr/bin/env node
import React from 'react';
import { render } from 'ink';
import { App } from '../src/App.js';

if (process.argv.includes('--version')) {
  const { default: pkg } = await import('../package.json', { with: { type: 'json' } });
  console.log(pkg.version);
  process.exit(0);
}

render(React.createElement(App));
