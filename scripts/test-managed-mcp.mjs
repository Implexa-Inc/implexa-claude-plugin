#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const manifest = JSON.parse(fs.readFileSync(path.join(root, '.mcp.json'), 'utf8'));
const source = JSON.stringify(manifest);
assert.deepEqual(Object.keys(manifest.mcpServers), ['implexa_managed']);
assert.equal(manifest.mcpServers.implexa_managed.command, '/bin/sh');
assert.deepEqual(manifest.mcpServers.implexa_managed.args,
  ['${CLAUDE_PLUGIN_ROOT}/scripts/implexa-claude-mcp']);
assert.doesNotMatch(source, /IMPLEXA_API_KEY|@implexa\/mcp-server|\bnpx\b/);

const installer = fs.readFileSync(path.join(root, 'scripts', 'install-user-hooks.sh'), 'utf8');
assert.doesNotMatch(installer, /mcpServers\.implexa\s*=|command:\s*"npx"|launchctl setenv IMPLEXA_API_KEY/);
assert.match(installer, /remove-legacy-claude-mcp\.sh/);

const shim = path.join(root, 'scripts', 'implexa-claude-mcp');
const tempHome = fs.mkdtempSync(path.join(os.tmpdir(), 'implexa-claude-mcp-test-'));
const capabilityRoot = fs.mkdtempSync('/private/tmp/implexa-codex-mcp-');
const socket = path.join(capabilityRoot, `broker-${'a'.repeat(48)}.sock`);
const locatorDir = path.join(tempHome, '.implexa');
const locator = path.join(locatorDir, 'codex-mcp.current');

fs.mkdirSync(locatorDir, { mode: 0o700 });
fs.writeFileSync(locator, socket, { mode: 0o600 });
fs.chmodSync(locator, 0o600);

const server = net.createServer((connection) => connection.pipe(connection));
await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(socket, resolve);
});

try {
  const child = spawn('/bin/sh', [shim], {
    env: { HOME: tempHome, PATH: '/usr/bin:/bin:/usr/sbin:/sbin' },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  child.stdin.end('{"jsonrpc":"2.0","id":1,"method":"ping"}\n');
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const code = await new Promise((resolve) => child.once('close', resolve));
  assert.equal(code, 0);
  assert.equal(stdout, '{"jsonrpc":"2.0","id":1,"method":"ping"}\n');
  assert.equal(stderr, '');

  fs.unlinkSync(locator);
  const offline = spawn('/bin/sh', [shim], {
    env: { HOME: tempHome, PATH: '/usr/bin:/bin:/usr/sbin:/sbin' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let offlineError = '';
  offline.stderr.on('data', (chunk) => { offlineError += chunk; });
  const offlineCode = await new Promise((resolve) => offline.once('close', resolve));
  assert.equal(offlineCode, 1);
  assert.match(offlineError, /Open Implexa, sign in/);
} finally {
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(capabilityRoot, { recursive: true, force: true });
  fs.rmSync(tempHome, { recursive: true, force: true });
}

process.stdout.write('managed Claude MCP: 8/8 passed\n');
