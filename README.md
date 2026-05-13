# Implexa — Skill recording for any AI session

> **Demonstrate any workflow once. Implexa captures it as a reusable, structured, measurable skill — shareable with your team or the world.**

The killer feature is the *first* feature you use. Start `/implexa:record-skill`, do your work normally, hit stop. Implexa interviews you for the gaps, then emits a 6-component skill (intent + inputs + procedure + decision points + output contract + outcome signal) you can invoke anytime, share with a domain-gated link, or post publicly.

**Free plan ships with credits.** No credit card required.

---

## Quick start (3 minutes)

### 1. Install

```bash
claude plugin install implexa
```

### 2. Get an API key

1. Sign up at **[implexa.ai/signup](https://implexa.ai/signup)** (Google / Microsoft SSO, or email).
2. Open **Settings → API Keys**.
3. Click **New key**, name it (e.g. "Claude Code"), copy the value — it shows **only once**.

### 3. Set it as an env var

**zsh** (macOS default):
```bash
echo 'export IMPLEXA_API_KEY="imp_live_..."' >> ~/.zshrc
source ~/.zshrc
```

**bash**:
```bash
echo 'export IMPLEXA_API_KEY="imp_live_..."' >> ~/.bashrc
source ~/.bashrc
```

**fish**:
```bash
set -Ux IMPLEXA_API_KEY "imp_live_..."
```

### 4. Record your first skill

In Claude Code:

```
/implexa:record-skill
```

Tell Claude what you're about to do, then do it. Hit "stop" when finished. Implexa interviews you for 2–4 questions, then saves the skill. Total time: ~3 minutes.

---

## What's in the plugin

### Skill recording flow
| Skill | What it does |
|---|---|
| `/implexa:record-skill` | The killer feature — demonstrate once → structured skill |
| `/implexa:save-this` | Post-hoc capture of work you just did (no demo flow) |

### Browse + invoke
| Skill | What it does |
|---|---|
| `/implexa:org-skills` | List your org's saved skills, invoke any |
| `/implexa:playbooks` | Browse the horizontal Playbook library |
| `/implexa:fork` | Clone any skill into your org for customization |

### Viral mechanics
| Skill | What it does |
|---|---|
| `/implexa:share-this` | Generate a share link — team-gated (same email domain) or public |
| `/implexa:skill-roi` | Outcome attribution rollup: which skills are working |

### Onboarding + admin
| Skill | What it does |
|---|---|
| `/implexa:get-me-started` | First-run activation — instant first skill |
| `/implexa:credits` | Check credit balance + plan |
| `/implexa:setup` | Connect integrations (email, calendar, CRM) |
| `/implexa:help` | Onboarding + FAQ |

---

## What's under the hood

- **~26 MCP tools** — Skill Graph (11), external data fetching (14: Fiber + Coresignal + Apollo), draft_message (Anthropic-direct)
- **Three capture surfaces** during recording: every MCP tool call (auto), non-tool actions you log via `record_demo_note` (manual), full host-side conversation transcript (UserPromptSubmit + Stop + PostToolUse hooks)
- **Domain-gated sharing** — team links only let users on your email domain install
- **Outcome attribution** — when a skill drives a real-world outcome (deal closed, meeting booked, candidate placed), it attributes back to the skill via last-touch
- **Renders wherever the LLM lives** — Claude Code, Claude Desktop, Claude.ai, Cursor, any MCP client

---

## Tech under the hood

- Streamable HTTP MCP transport
- Anthropic SDK (Haiku for skill authoring + interview generation)
- Supabase (Postgres + Auth + Storage + Realtime)
- Fiber AI / Coresignal / Apollo for external data v1
- Exa + Browserbase coming in v2

---

## License

MIT
