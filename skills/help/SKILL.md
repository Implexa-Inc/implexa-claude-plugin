---
description: 'Show how Implexa works (app-first) + your current credit balance + plan tier. Manual-only (user must explicitly type /implexa:help). Absorbs the old /implexa:credits utility; the balance is shown inline at the top of this page.'
disable-model-invocation: true
---

# Implexa: how it works

When the user invokes `/implexa:help`, return the page below as a markdown reply, with one substitution: the credit balance block at the top is populated from a live `get_credits` call. Don't paraphrase the rest, don't expand, don't add your own commentary. Just print this page.

## Step 1 - Fetch the credit balance (free, no-side-effect)

Call **`get_credits`**. The response shape:

```
{
  credits:        <remaining>,
  plan_display:   'Free' | 'Starter' | 'Growth' | 'Pro' | 'Scale',
  plan_status:    'active' | 'past_due' | 'canceled',
  plan_quota:     <total monthly credits>,
  usage_pct:      <0-100>,
  low_balance:    <bool, true if remaining < 100>,
  is_admin_bridge:<bool>,
  is_enterprise:  <bool>,
  billing_url:    'https://admin.implexa.ai/p2p/billing',
}
```

If the call errors (key missing / revoked / network), still render the page but replace the balance block with: `> ⚠️ Couldn't reach Implexa. Re-run the installer at https://implexa.ai/install if this persists.`

## Step 2 - Render the page

Use this template, substituting the balance values from Step 1:

```
### 💳 Your account

**Plan**: <plan_display> · <plan_status>
**Credits**: <credits> / <plan_quota>  (<100 - usage_pct>% available)
```

If `low_balance: true`, append: `⚠️ Running low. Top up at <billing_url>.`
If `is_admin_bridge: true` OR `is_enterprise: true`, replace the credits line with: `**Enterprise account** - org-level usage at https://admin.implexa.ai/analytics/usage-tool.`

Then below the balance, render this page verbatim:

```
### 🎛️ Implexa is app-first

You build, run, approve, and schedule your agents in the **Implexa app** — Claude runs them in the background.

| where | what you do there |
|---|---|
| **app.implexa.ai** | Build an agent from a plain-language description, browse your library + the community catalog, run an agent on demand, put it on a schedule, and approve runs that paused for your sign-off |
| **Here, in Claude** | Just ask in natural language. The Implexa MCP tools are exposed to the model, so most asks route without a slash command |
| **In the background** | Scheduled and on-demand agents fire on their own and deliver to your dashboard, email, or Slack — no session needed |

### 🗣️ Or just ask in natural language

There's no command to memorize. Describe what you want and Implexa's MCP tools handle it. Examples:

- `Build me an agent that drafts a weekly market report`  →  composes a new agent via `generate_workflow`
- `Find me an agent for cold outreach`  →  searches your library + the community catalog
- `Run my morning brief`  →  runs it via `run_agent_now` / `orchestrate_skills`
- `Schedule the prospecting agent every weekday at 9am`  →  registers it via `schedule_skill`
- `Which of my agents drove the most revenue?`  →  reads attribution via `attribute_skill_outcome`

### ⚙️ The agent lifecycle

1. **Build it** — describe a recurring job and Implexa builds a ready-to-run agent from verified components, or finds the best-fit one in the catalog.
2. **Run it** — on demand, or put it on a **schedule** so it runs itself and delivers to your inbox.
3. **Approve it** — when an agent pauses before a consequential step (publishing, sending, spending), it holds for your one-tap approval in the app.
4. **It improves** — every run hardens the agent for the next one. Focused single-task agents also run in Claude Code, Cursor, Codex, Gemini CLI, and 30+ agents.

### 📦 What's free vs. what costs credits

**Free forever**: browsing your library, running agents you own, `get_credits`, `/implexa:help`.

**Costs credits**: building/saving an agent, external-data lookups (Fiber / Coresignal / Apollo), Haiku draft passes.

### 🔗 Useful links

- App (build, run, approve, schedule): https://app.implexa.ai
- Settings + API keys: https://app.implexa.ai/settings/api-keys
- Billing: https://admin.implexa.ai/p2p/billing
- Install / reinstall: https://implexa.ai/install
```

## Step 3 - Notes for the model

- This page replaces both the old `/implexa:help` (the command catalogue) and the old `/implexa:credits` (credit balance display). Both are folded in.
- Implexa is now **app-first**: the slash-command surface was retired in favor of the Implexa app + natural-language asks. `/implexa:help` is the only command a user types directly; everything else lives in the app or routes through the MCP tools by just asking.
- Keep the balance display under 4 lines. Users want a number, not a tutorial.
- For `low_balance: true`, lead with the warning so users adjust before kicking off a credit-heavy agent run.
- For admin-bridged enterprise accounts, don't echo the placeholder 999999 credit count. Just say "enterprise" and point at the org analytics URL.
