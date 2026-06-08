#!/usr/bin/env node
/**
 * apply-permission-manifest.mjs — pre-grant a scheduled agent's permission
 * manifest so an UNATTENDED run never stalls on an interactive permission prompt.
 *
 * The problem (observed live 2026-06-08): an agent runs in the user's own Claude
 * Code (presence not runtime), so a scheduled run inherits its permission
 * prompts; with nobody there to click "Allow Claude to fetch implexa.ai?", the
 * run is a dead stop with no error, and silence reads as success.
 *
 * The fix has two writes, both ADDITIVE and idempotent:
 *
 *   1. ALLOWLIST -> ~/.claude/settings.json  permissions.allow
 *      Claude Code's docs confirm allow rules in the user settings apply to
 *      scheduled-task sessions, regardless of the task's working folder. This is
 *      the guaranteed layer: the manifest's exact rules (e.g.
 *      "WebFetch(domain:implexa.ai)", "WebSearch", "mcp__implexa__*") are merged
 *      in, so those tools run without a prompt. Harmless to interactive sessions
 *      (it only pre-approves those specific scoped tools).
 *
 *   2. FAIL-FAST -> ~/.claude/scheduled-tasks/.claude/settings.json
 *      permissions.defaultMode "dontAsk" + the same allow rules. Scheduled tasks
 *      live under ~/.claude/scheduled-tasks/<taskId>/, so a settings file at that
 *      tree's root applies to scheduled runs but NOT to the user's normal
 *      interactive sessions (which run in real project dirs). "dontAsk"
 *      auto-DENIES any tool not in the allowlist and continues, so an UNFORESEEN
 *      tool fails fast and visibly (one-tap fixable) instead of hanging forever.
 *      Best-effort: if the runtime does not resolve this scoped file, layer 1
 *      still prevents the common stall.
 *
 * NEVER writes a blanket bypass: only the agent's scoped rules are added, and
 * defaultMode "dontAsk" is the safe (deny) default, never "bypassPermissions".
 *
 * Usage:
 *   node apply-permission-manifest.mjs --file <manifest.json> [--dry-run]
 *   echo '<manifest json>' | node apply-permission-manifest.mjs [--dry-run]
 *
 * The manifest JSON is the object schedule_skill returns as `permissionManifest`
 * ({ rules: [...], summary, ... }). Reads from --file or stdin; no shell-escaping
 * pitfalls. Exit 0 on success (prints what changed); non-zero on a hard error.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync, renameSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? (process.argv[i + 1] || true) : null;
}
const DRY = process.argv.includes('--dry-run');

function fail(msg) { process.stderr.write(`apply-permission-manifest: ${msg}\n`); process.exit(1); }

// ── read the manifest (file or stdin) ───────────────────────────────────────
let raw;
const file = arg('--file');
if (file && typeof file === 'string') {
  try { raw = readFileSync(file, 'utf8'); } catch (e) { fail(`could not read --file ${file}: ${e.message}`); }
} else {
  try { raw = readFileSync(0, 'utf8'); } catch { /* no stdin */ }
}
if (!raw || !raw.trim()) fail('no manifest provided (pass --file <path> or pipe JSON on stdin)');

let manifest;
try { manifest = JSON.parse(raw); } catch (e) { fail(`manifest is not valid JSON: ${e.message}`); }

const rules = Array.isArray(manifest.rules) ? manifest.rules.filter((r) => typeof r === 'string' && r.trim()) : [];
if (!rules.length) fail('manifest has no rules to grant');

// Defense in depth: refuse anything that looks like a blanket bypass even if a
// malformed manifest slipped one in. Pre-grant is scoped rules only.
const BANNED = new Set(['*', 'Bash', 'bypassPermissions']);
for (const r of rules) {
  if (BANNED.has(r) || /bypass/i.test(r)) fail(`refusing to grant a blanket/bypass rule: ${JSON.stringify(r)}`);
}

// ── JSON helpers: read-or-default, atomic write, additive merge ──────────────
function readJson(path) {
  if (!existsSync(path)) return {};
  try { return JSON.parse(readFileSync(path, 'utf8')) || {}; }
  catch (e) { fail(`existing ${path} is not valid JSON, refusing to overwrite: ${e.message}`); }
}
function writeJson(path, obj) {
  if (DRY) return;
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.implexa.tmp`;
  writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n');
  renameSync(tmp, path); // atomic on the same filesystem
}

// Merge `rules` into settings.permissions.allow (creating the path), preserving
// everything else. Returns the list of rules actually added (for reporting).
function mergeAllow(settings, opts = {}) {
  if (!settings.permissions || typeof settings.permissions !== 'object') settings.permissions = {};
  const p = settings.permissions;
  if (!Array.isArray(p.allow)) p.allow = [];
  const have = new Set(p.allow);
  const added = [];
  for (const r of rules) if (!have.has(r)) { p.allow.push(r); have.add(r); added.push(r); }
  if (opts.dontAsk && p.defaultMode !== 'dontAsk') p.defaultMode = 'dontAsk';
  return added;
}

// ── layer 1: user settings allowlist ────────────────────────────────────────
const userSettingsPath = join(homedir(), '.claude', 'settings.json');
const userSettings = readJson(userSettingsPath);
const addedUser = mergeAllow(userSettings); // allowlist only, never touch the user's interactive defaultMode
writeJson(userSettingsPath, userSettings);

// ── layer 2: scheduled-run-scoped fail-fast ─────────────────────────────────
const schedSettingsPath = join(homedir(), '.claude', 'scheduled-tasks', '.claude', 'settings.json');
const schedSettings = readJson(schedSettingsPath);
const addedSched = mergeAllow(schedSettings, { dontAsk: true });
writeJson(schedSettingsPath, schedSettings);

// ── report ──────────────────────────────────────────────────────────────────
const out = {
  ok: true,
  dryRun: DRY,
  summary: manifest.summary || null,
  granted: rules,
  userSettings: { path: userSettingsPath, added: addedUser },
  scheduledScoped: { path: schedSettingsPath, added: addedSched, defaultMode: 'dontAsk' },
};
process.stdout.write(JSON.stringify(out, null, 2) + '\n');
