---
description: 'Show the 7 Implexa commands + your current credit balance + plan tier. Manual-only — user must explicitly type /implexa:help. Absorbs the old /implexa:credits utility — the balance is now shown inline at the top of this page.'
disable-model-invocation: true
---

# Implexa — what can I do?

When the user invokes `/implexa:help`, return the catalogue below VERBATIM as a markdown reply, with one substitution: the credit balance block at the top is populated from a live `get_credits` call. Don't paraphrase the rest, don't expand, don't add your own commentary — just print this page.

## Step 1 — Fetch the credit balance (free, no-side-effect)

Call **`get_credits`**. The response shape:

```
{
  credits:        <remaining>,
  plan_display:   'Free' | 'Starter' | 'Growth' | 'Pro' | 'Scale',
  plan_status:    'active' | 'past_due' | 'canceled',
  plan_quota:     <total monthly credits>,
  usage_pct:      <0-100>,
  low_balance:    <bool — true if remaining < 100>,
  is_admin_bridge:<bool>,
  is_enterprise:  <bool>,
  billing_url:    'https://admin.implexa.ai/p2p/billing',
}
```

If the call errors (key missing / revoked / network), still render the catalogue but replace the balance block with: `> ⚠️ Couldn't reach Implexa — re-run the installer at https://implexa.ai/install if this persists.`

## Step 2 — Render the page

Use this template, substituting the balance values from Step 1:

```
### 💳 Your account

**Plan**: <plan_display> · <plan_status>
**Credits**: <credits> / <plan_quota>  (<100 - usage_pct>% available)
```

If `low_balance: true`, append: `⚠️ Running low — top up at <billing_url>.`
If `is_admin_bridge: true` OR `is_enterprise: true`, replace the credits line with: `**Enterprise account** — org-level usage at https://admin.implexa.ai/analytics/usage-tool.`

Then below the balance, render this catalogue verbatim:

```
### ⚡ The 7 commands

| command | what it does |
|---|---|
| `/implexa:suggest [for X]` | Find skills + workflows: active search if you give a query, passive buffer pull if you don't |
| `/implexa:run <what you want>` | Find + run the best fit: leads with a whole-job **workflow** when one matches, else the best skill from your library or the cross-vendor graph |
| `/implexa:record` | Capture your work as a reusable **skill** OR a multi-step **workflow** (schedulable, shareable) |
| `/implexa:my-skills [scope]` | Browse your library: `personal` (default), `team`, `public`, or `workflows` (the whole jobs you saved) |
| `/implexa:schedule <thing> <cadence>` | Put a skill or workflow on autopilot: dashboard, email, or Slack delivery |
| `/implexa:share-this` | Share a **skill** (team/public install link) or a **workflow** (publish to the community for karma) |
| `/implexa:help` | This page |

### 🗣️ Or just ask in natural language

The 7 commands cover the high-traffic verbs. For anything else, just ask — Implexa's MCP tools are exposed to the model and most common asks route correctly without a slash. Examples:

- `Fork the daily-prospecting skill into my org`  →  forks via `fork_org_skill`
- `Give me my morning brief`  →  orchestrates your morning chain via `orchestrate_skills`
- `Which of my skills drove the most revenue?`  →  reads attribution via `attribute_skill_outcome`
- `Publish my X skill to ClawHub`  →  uses the clawhub CLI + `get_skill_content`

### 🎬 The killer flow

Two ways to get a reusable, schedulable **workflow**, a whole job run end to end, not a single skill:

- **Prompt it**: describe a recurring job and Implexa builds the workflow from verified skills (`/implexa:run`, or just ask).
- **Capture it**: do the job once and say "save this as a workflow"; Implexa reconstructs the chain (`/implexa:record`).

Either way you get a workflow you can **run on your own agent**, put on a **schedule** (it delivers to your inbox on its own), browse anytime (`/implexa:my-skills workflows`), and **share** with the community for karma, and every run hardens it for the next person. Single procedures still capture as a 6-component **skill** that runs in Claude Code, Cursor, Codex, Gemini CLI, and 30+ agents.

### 📦 What's free vs. what costs credits

**Free forever**: `list_org_skills`, `apply_org_skill`, `get_credits`, viewing share previews, `/implexa:help`, `/implexa:suggest`, `/implexa:my-skills`.

**Costs credits**: capture + interview (`/implexa:record`), share-link mint (`/implexa:share-this`), external-data lookups (Fiber / Coresignal / Apollo), Haiku draft passes.

### 🔗 Useful links

- Dashboard: https://app.implexa.ai
- Settings + API keys: https://app.implexa.ai/settings/api-keys
- Billing: https://admin.implexa.ai/p2p/billing
- Install / reinstall: https://implexa.ai/install
```

## Step 3 — Filter (optional)

If the user passed text after `/implexa:help` (in `$ARGUMENTS`) and it matches a command name (e.g. `record`, `share`, `schedule`), narrow the table to just that row and skip the natural-language + killer-flow sections. Otherwise show everything.

## Notes for the model

- This page replaces both the old `/implexa:help` (the long 18-command catalogue) and the old `/implexa:credits` (credit balance display). Both are now folded in.
- Keep the balance display under 4 lines. Users want a number, not a tutorial.
- For `low_balance: true`, lead with the warning so users adjust before kicking off a credit-heavy workflow.
- For admin-bridged enterprise accounts, don't echo the placeholder 999999 credit count — just say "enterprise" and point at the org analytics URL.
- The natural-language fallback section is intentional voice — users have memorized the old 18 commands; this resets the mental model to "ask, don't memorize."
