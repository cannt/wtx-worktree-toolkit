#!/usr/bin/env node
'use strict';

// Thin Node shim around the bash bootstrap. There is no JavaScript install
// logic here on purpose — bootstrap.sh is the single source of truth. This
// just lets people run `npx wtx-toolkit install` the way bmad ships
// `npx bmad-method install`.
//
// Resolution order for the bootstrap script:
//   1. bundled next to the package (copied in by `prepack` at publish time)
//   2. the repo-root bootstrap.sh (running from a source checkout)
//   3. download from the public raw URL and pipe to bash (last resort)

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const RAW_URL =
  process.env.WTX_BOOTSTRAP_URL ||
  'https://raw.githubusercontent.com/cannt/wtx-worktree-toolkit/main/bootstrap.sh';

const args = process.argv.slice(2);

function findBundledBootstrap() {
  const candidates = [
    path.join(__dirname, '..', 'bootstrap.sh'), // published layout
    path.join(__dirname, '..', '..', 'bootstrap.sh'), // source checkout (npm/ subdir)
  ];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) return p;
    } catch (_) {
      /* ignore */
    }
  }
  return null;
}

function run() {
  const bootstrap = findBundledBootstrap();
  let result;

  if (bootstrap) {
    result = spawnSync('bash', [bootstrap, ...args], { stdio: 'inherit' });
  } else {
    // No bundled script — stream it from the public URL through bash.
    // `bash -s -- <args>` forwards our CLI flags to the piped script.
    const shArgs = args.map((a) => `'${String(a).replace(/'/g, "'\\''")}'`).join(' ');
    const cmd = `curl -fsSL '${RAW_URL}' | bash -s -- ${shArgs}`;
    result = spawnSync('bash', ['-c', cmd], { stdio: 'inherit' });
  }

  if (result.error) {
    if (result.error.code === 'ENOENT') {
      console.error('wtx-toolkit: could not find `bash` on PATH — wtx requires bash.');
    } else {
      console.error('wtx-toolkit: ' + result.error.message);
    }
    process.exit(1);
  }
  process.exit(result.status === null ? 1 : result.status);
}

run();
