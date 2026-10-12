#!/usr/bin/env node
if (process.argv.includes('--version')) {
  const { default: pkg } = await import('../package.json', { with: { type: 'json' } });
  console.log(pkg.version);
  process.exit(0);
}

// React's development build records a performance.measure entry for every
// component render, and Node never clears them, so a long-running portwatch
// leaks memory (past 1GB after about a day). NODE_ENV has to be set before
// React is first imported, which is why react/ink/App are imported
// dynamically below rather than at the top of the file.
process.env.NODE_ENV ??= 'production';

const { default: React } = await import('react');
const { render } = await import('ink');
const { App } = await import('../src/App.js');

render(React.createElement(App));
