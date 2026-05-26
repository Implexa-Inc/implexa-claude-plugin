# Implexa — The skill graph for AI work.

> **Demonstrate any workflow once. Capture decision traces. Share with your team. Measure what actually worked. Compatible with the [agentskills.io](https://agentskills.io) open standard — your skills run in Claude Code, Cursor, Gemini CLI, and 30+ more agents.**

[![Built on agentskills.io](https://img.shields.io/badge/Built%20on-agentskills.io-22c55e?style=flat-square)](https://agentskills.io)
[![MIT plugin](https://img.shields.io/badge/Plugin-MIT-blue?style=flat-square)](https://github.com/Implexa-Inc/implexa-claude-plugin/blob/main/LICENSE)
[![Free forever](https://img.shields.io/badge/Free%20tier-Forever-orange?style=flat-square)](https://implexa.ai)

```bash
curl -fsSL https://core.implexa.ai/install.sh | bash
```

One paste, ~30 seconds. Browser opens for sign-up / sign-in, you approve, terminal finishes the rest. Installs the API key, hooks, plugin, and MCP wiring — all in one go.

Free forever. No credit card. MIT-licensed plugin · hosted service.

[**implexa.ai**](https://implexa.ai) · [Public skills](https://app.implexa.ai/skills) · [Dashboard](https://app.implexa.ai) · [Skill format docs](https://implexa.ai/claude-skills)

---

## What it does

`/implexa:record` is the killer feature. Demonstrate any workflow once. Implexa captures every tool call + conversation turn, runs a structured Haiku-powered interview to lock the intent, and emits a **6-component skill** (intent + inputs + procedure + decision points + output contract + outcome signal) that's:

- **Replayable** — `/implexa:run "the prospecting one"` fuzzy-matches your library and re-executes
- **Measurable** — outcomes attribute back via last-touch within a 30-day window
- **Portable** — works across Claude Code CLI, Claude Code Desktop, Cowork, and Chat
- **Shareable** — team-gated (same email domain) or public links; public shares unlock Founding Creator status

---

## Quick start

### 1. Install

```bash
curl -fsSL https://core.implexa.ai/install.sh | bash
```

Works on macOS, Linux, and Windows (WSL). Browser opens to approve the install — once you click Approve, the terminal finishes installing the API key, hooks, plugin, and MCP wiring.

### 2. Verify

Launch Claude Code:

```bash
claude
```

Verify the connection:

```
/implexa:help
```

You should see the 7 commands + your current credit balance + plan tier.

### 3. Record your first skill

```
/implexa:record
```

Tell Claude what you're about to demonstrate, then do your work normally. Implexa watches in the background. When you're done, it asks 2–4 questions to fill in gaps, then saves the skill. Total time: ~3 minutes.

### 4. Re-run anywhere

```
/implexa:run "the X one"
```

Fuzzy match against your library. Claude picks the right skill and applies it with your current context.

---

## The Skill Graph flywheel

Every team has a few power users with integrations already wired up (HubSpot, Salesforce, Linear, GitHub, Apollo, Coresignal, etc.). Implexa turns their expertise into portable skills the rest of the org can invoke.

```
1. Power user connects tools to Claude
   ↓
2. They record a skill that uses those tools
   ↓
3. Implexa captures the tool chain in the skill
   ↓
4. A teammate runs the skill via /implexa:run
   ↓
5. If the teammate is missing a required tool, Implexa surfaces an install hint
   ↓
6. They install. Run the skill. Get the outcome.
```

Everyone in the org now has the power user's stack — without having to discover, evaluate, and learn each integration. Power users get rewarded with **Founding Creator** status: unlimited captures + a free Pro seat for life.

---

## What's in the plugin

### The 7 visible commands (0.16.0+)

| Skill | What it does |
|---|---|
| `/implexa:suggest [for X]` | Find skills — active search if you give a query, passive buffer pull if you don't |
| `/implexa:run <skill or prompt>` | Find + apply the best-fit skill from your library OR the cross-vendor graph |
| `/implexa:record` | Capture a workflow as a skill — new from demo, post-hoc save, or update existing via re-record |
| `/implexa:my-skills [scope]` | Browse libraries — `personal` (default), `team`, `org`, `public` (Playbooks + cross-org) |
| `/implexa:schedule <skill> <cadence>` | Schedule any skill to run on a recurrence — dashboard or Slack delivery |
| `/implexa:share-this` | Generate a share link — team-gated (your domain) or public (anywhere) |
| `/implexa:help` | This list + your current credit balance + plan tier |

Plus one internal: `/implexa:run-scheduled` (callback fired by Claude Code's scheduled-tasks runtime — not user-invocable).

### Why only 7?

We consolidated from 20 commands (0.15.0) to 7 (0.16.0) because the long tail (fork, morning brief, skill-roi, clawhub publish, get-me-started, setup-hooks, etc.) is covered better by natural-language invocation. The MCP tools that powered the old commands are all still exposed — the model routes asks like `"give me my morning brief"`, `"fork the X skill"`, `"publish my Y to ClawHub"`, `"show me skill ROI"` straight to the underlying tool. No memorization needed.

The old commands that merged into survivors:
- `/implexa:save-this` + `/implexa:update-skill` → folded into `/implexa:record` (three entry intents in one flow)
- `/implexa:org-skills` + `/implexa:playbooks` → folded into `/implexa:my-skills` via the `scope` parameter
- `/implexa:credits` → folded into `/implexa:help` (balance now shown inline)

---

## Under the hood

- **~30 MCP tools** — Skill Graph (11), external data fetching (14: Fiber AI + Coresignal + Apollo), `draft_message`, `revoke_share_link`, `get_credits`
- **Three capture surfaces** during recording:
  - Every MCP tool call (auto, via `PostToolUse` hook)
  - Non-tool actions you log via `record_demo_note` (manual)
  - Full host-side conversation transcript (via `UserPromptSubmit` + `Stop` hooks)
- **6-component skill structure** — intent, inputs, procedure, decision points, output contract, outcome signal — generated by Haiku from the captured trace + your interview answers
- **Domain-gated sharing** — team links only let users on your email domain install
- **Outcome attribution** — last-touch within a 30-day window from CRM/ATS/calendar events
- **Runtime hint propagation** — `apply_org_skill` returns the skill's required tool chain so consumers get a clear "install this integration" hint if a tool the skill needs isn't available in their session
- **Routine portability** — skills that use Claude Code's `RemoteTrigger` to set up daily schedules carry the cron + prompt spec; forkers get the schedule wired automatically (no manual `/schedule` step)
- **PII scrubbing** — input + output passes through a dedicated scrubber before LLM calls and persistence
- **Renders wherever the LLM lives** — Claude Code, Claude Desktop, Cowork, Claude chat (via Custom Connector), Cursor, any MCP client

---

## Installation paths

### Universal (recommended)
```bash
curl -fsSL https://core.implexa.ai/install.sh | bash
```
Browser-based device-auth flow. Works on macOS, Linux, Windows (WSL). No tokens, no manual key handling.

### Visual install (Claude Code Desktop / Cowork)
Customize panel → Personal plugins → + Create plugin → **Add marketplace**:
```
https://github.com/Implexa-Inc/implexa-claude-plugin
```

### Claude chat (Desktop) — Custom Connector URL
Customize → Connectors → + → Add custom connector:
```
https://core.implexa.ai/api/v2/mcp?api_key=YOUR_KEY
```
(Sign up to generate your API key — this is the only surface that still needs a manually-pasted key.)

### Uninstall / reset

```bash
curl -fsSL https://core.implexa.ai/uninstall.sh | bash
```
Idempotent. Reverses everything the installer set up (config files, hooks, MCP wiring, plugin, launchctl env vars). Doesn't revoke cloud API keys — do that at [Connected installs](https://app.implexa.ai/settings/api-keys).

---

## Tech under the hood

- **MCP transport**: Streamable HTTP
- **Skill authoring**: Anthropic SDK (Claude Haiku for interview question generation + skill synthesis)
- **Backend**: Node.js + Express + Supabase (Postgres + Auth + RLS + Realtime)
- **External data**: Fiber AI, Coresignal, Apollo
- **Hooks**: bash-based event handler at `~/.claude/implexa-hook.sh`, sourced from `~/.claude/implexa.env`
- **Plugin distribution**: marketplace clone to `~/.claude/plugins/marketplaces/implexa/`, copied to versioned cache path
- **Auth**: RFC 8628-style device-flow with 10-min single-use tokens; backend mints fresh API keys on approval

---

## Pricing

- **Free forever** — 5 skill captures / month, unlimited skill runs, public sharing
- **Founding Creator** (free perk) — share 1 public skill, unlock unlimited captures + a free Pro seat for life
- **Pro** — $19/mo or $190/year — unlimited captures, team library, audit log, SSO

---

## What's open source vs. hosted

| Component | Status | Why |
|---|---|---|
| This plugin (`implexa-claude-plugin`) | **MIT licensed** | The plugin runs on your machine. We want anyone to be able to audit exactly what it captures + sends to our backend. |
| Install scripts (`install.sh`, `uninstall.sh`) | **MIT licensed** | Same reason — they run on your machine. |
| `~/.claude/implexa-hook.sh` (the hook launcher) | **MIT licensed** | Same reason. |
| Backend API (`core.implexa.ai`) | Hosted SaaS | Receives skill captures, MCP requests, attribution events. Closed source. Standard SaaS model. |
| Dashboard (`app.implexa.ai`) | Hosted SaaS | The web UI for browsing + sharing skills. Source is currently visible on GitHub but not formally licensed. |
| Skill Graph data | Hosted | Your skills live in our database. RLS isolates per-org. Export available via `/api/v2/skills` for compliance / portability. |

We follow the same model as Stripe CLI, Supabase CLI, and fly.io — open the client (the thing on your laptop) so it's auditable, run the service (the thing that holds your data) as a managed SaaS.

## License

[MIT](./LICENSE). Plugin source + install scripts only. The backend service is not covered.

---

## Links

- 🌐 [implexa.ai](https://implexa.ai) — marketing site
- 🎯 [app.implexa.ai/skills](https://app.implexa.ai/skills) — public skills directory
- 📊 [app.implexa.ai/install](https://app.implexa.ai/install) — full install guide (logged-in)
- 💬 [hello@implexa.ai](mailto:hello@implexa.ai) — questions, feedback, bug reports
