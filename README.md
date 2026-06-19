# Implexa — Agents that run on their own.

> **Build, run, and approve agents in the Implexa app. Claude runs them in the background — on demand or on a schedule. Compatible with the [agentskills.io](https://agentskills.io) open standard — your agents run in Claude Code, Cursor, Gemini CLI, and 30+ more agents.**

[![Built on agentskills.io](https://img.shields.io/badge/Built%20on-agentskills.io-22c55e?style=flat-square)](https://agentskills.io)
[![MIT plugin](https://img.shields.io/badge/Plugin-MIT-blue?style=flat-square)](https://github.com/Implexa-Inc/implexa-claude-plugin/blob/main/LICENSE)
[![Free forever](https://img.shields.io/badge/Free%20tier-Forever-orange?style=flat-square)](https://implexa.ai)

```bash
curl -fsSL https://core.implexa.ai/install.sh | bash
```

One paste, ~30 seconds. Browser opens for sign-up / sign-in, you approve, terminal finishes the rest. Installs the API key, hooks, plugin, and MCP wiring — all in one go.

Free forever. No credit card. MIT-licensed plugin · hosted service.

[**implexa.ai**](https://implexa.ai) · [Public agents](https://app.implexa.ai/skills) · [App](https://app.implexa.ai) · [Agent format docs](https://implexa.ai/claude-skills)

---

## What it does

Implexa is **app-first**: you build, run, approve, and schedule your agents in the [Implexa app](https://app.implexa.ai), and Claude runs them in the background.

Describe a recurring job in plain language and Implexa builds a ready-to-run **agent** — or finds the best-fit one from a 40,000+ cross-vendor catalog (Anthropic, Cursor, Smithery, ClawHub, Skills.sh, GitHub, and more), each built on verified open-source modules (license-safe, provenance-checked, advisory-scanned). Every agent is:

- **Runnable** — on demand from the app, or on a schedule that delivers to your dashboard, email, or Slack
- **Approvable** — when an agent pauses before a consequential step (publish, send, spend), it holds for your one-tap approval
- **Measurable** — outcomes attribute back via last-touch within a 30-day window
- **Portable** — works across Claude Code CLI, Claude Code Desktop, Cowork, and Chat, plus Cursor, Codex, Gemini CLI, and 30+ agents

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

You should see how Implexa works + your current credit balance + plan tier.

### 3. Build your first agent

Open the app at [app.implexa.ai](https://app.implexa.ai) and describe a recurring job — or just ask Claude in natural language:

```
Build me an agent that drafts a weekly market report
```

Implexa composes the agent from verified components. From the app you can run it on demand, put it on a schedule, and approve runs that pause for your sign-off.

### 4. Run it anywhere

Run on demand or on a schedule; results land on your dashboard (and Slack/email if configured). Scheduled and on-demand runs fire in the background — no session needs to be open.

---

## The agent catalog flywheel

Every team has a few power users with integrations already wired up (HubSpot, Salesforce, Linear, GitHub, Apollo, Coresignal, etc.). Implexa turns their expertise into portable agents the rest of the org can run.

```
1. Power user connects tools to Claude
   ↓
2. They build an agent that uses those tools
   ↓
3. Implexa captures the tool chain in the agent
   ↓
4. A teammate runs the agent from the app
   ↓
5. If the teammate is missing a required tool, Implexa surfaces an install hint
   ↓
6. They install. Run the agent. Get the outcome.
```

Everyone in the org now has the power user's stack — without having to discover, evaluate, and learn each integration. Power users get rewarded with **Founding Creator** status: unlimited builds + a free Pro seat for life.

---

## What's in the plugin

The Implexa app is the control surface. The Claude plugin is the thin background runtime that lets Claude run your agents and stay in sync with the app. It ships:

| Component | What it does |
|---|---|
| `/implexa:help` | How Implexa works + your current credit balance + plan tier (the only user-typed command) |
| `/implexa:run-scheduled` | Internal callback fired by Claude Code's scheduled-tasks runtime when a scheduled agent runs — not user-invocable |
| Session hooks | Drain pending on-demand run requests at session start, and keep unattended runs from stalling on a permission prompt |
| MCP wiring | Exposes the Implexa MCP tools to the model so natural-language asks ("build me an agent for X", "run my morning brief") route correctly |

Everything else — building, browsing, running, scheduling, approving, and sharing agents — lives in the [Implexa app](https://app.implexa.ai) or routes through the MCP tools when you ask in natural language. There's no slash-command surface to memorize.

---

## Under the hood

- **~30 MCP tools** — agent catalog + recommender, external data fetching (Fiber AI + Coresignal + Apollo), `draft_message`, `revoke_share_link`, `get_credits`, and the scheduled-run + propose-next-agents engine
- **6-component agent structure** — intent, inputs, procedure, decision points, output contract, outcome signal — generated by Haiku from the agent's source and your description
- **Background execution** — scheduled and on-demand agents fire via Claude Code's scheduled-tasks runtime through the `/implexa:run-scheduled` callback; output is persisted and delivered to dashboard / Slack / email
- **Approval gates** — an agent that reaches a consequential or expensive step holds the run for one-tap human approval instead of guessing
- **Self-improvement loop** — each run collects lightweight feedback that feeds the next run, and a successful run proposes the next 1–3 agents worth building
- **Domain-gated sharing** — team links only let users on your email domain install
- **Outcome attribution** — last-touch within a 30-day window from CRM/ATS/calendar events
- **Runtime hint propagation** — applying an agent returns its required tool chain so consumers get a clear "install this integration" hint if a tool the agent needs isn't available
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
- **Agent authoring**: Anthropic SDK (Claude Haiku for agent synthesis)
- **Backend**: Node.js + Express + Supabase (Postgres + Auth + RLS + Realtime)
- **External data**: Fiber AI, Coresignal, Apollo
- **Hooks**: plugin-packaged background hooks (queue drain on session start, permission-stall safety), sourced from `~/.claude/implexa.env`
- **Plugin distribution**: marketplace clone to `~/.claude/plugins/marketplaces/implexa/`, copied to versioned cache path
- **Auth**: RFC 8628-style device-flow with 10-min single-use tokens; backend mints fresh API keys on approval

---

## Pricing

- **Free forever** — 5 agent builds / month, unlimited agent runs, public sharing
- **Founding Creator** (free perk) — share 1 public agent, unlock unlimited builds + a free Pro seat for life
- **Pro** — $19/mo or $190/year — unlimited builds, team library, audit log, SSO

---

## What's open source vs. hosted

| Component | Status | Why |
|---|---|---|
| This plugin (`implexa-claude-plugin`) | **MIT licensed** | The plugin runs on your machine. We want anyone to be able to audit exactly what it does + sends to our backend. |
| Install scripts (`install.sh`, `uninstall.sh`) | **MIT licensed** | Same reason — they run on your machine. |
| Backend API (`core.implexa.ai`) | Hosted SaaS | Receives agent definitions, MCP requests, attribution events. Closed source. Standard SaaS model. |
| Dashboard (`app.implexa.ai`) | Hosted SaaS | The web UI for building + running + sharing agents. Source is currently visible on GitHub but not formally licensed. |
| Agent catalog data | Hosted | Your agents live in our database. RLS isolates per-org. Export available via `/api/v2/skills` for compliance / portability. |

We follow the same model as Stripe CLI, Supabase CLI, and fly.io — open the client (the thing on your laptop) so it's auditable, run the service (the thing that holds your data) as a managed SaaS.

## License

[MIT](./LICENSE). Plugin source + install scripts only. The backend service is not covered.

---

## Links

- 🌐 [implexa.ai](https://implexa.ai) — marketing site
- 🎯 [app.implexa.ai/skills](https://app.implexa.ai/skills) — public agents directory
- 📊 [app.implexa.ai/install](https://app.implexa.ai/install) — full install guide (logged-in)
- 💬 [hello@implexa.ai](mailto:hello@implexa.ai) — questions, feedback, bug reports
