---
description: Show the user's current Implexa credit balance, plan tier, and usage. Manual-only — user must explicitly type /implexa:credits.
disable-model-invocation: true
---

# Credits & plan

User invoked `/implexa:credits`. Return their real credit balance, plan, and usage so they know whether they can afford the next workflow.

## Step 1 — Fetch the data

Call **`get_credits`** (free, Mongo lookup only). The response shape:

```
{
  credits: <number remaining>,
  plan: 'free' | 'starter' | 'growth' | 'pro' | 'scale',
  plan_display: 'Free' | 'Starter' | 'Growth' | 'Pro' | 'Scale',
  plan_status: 'active' | 'past_due' | 'canceled',
  plan_quota: <total monthly credits the plan ships with>,
  credits_used: <plan_quota - credits>,
  usage_pct: <0-100>,
  low_balance: <bool — true if remaining < 100>,
  is_admin_bridge: <bool — true if this is a bridged-enterprise stub with a placeholder 999999 value>,
  is_enterprise: <bool>,
  billing_url: 'https://admin.implexa.ai/p2p/billing',
  settings_url: 'https://admin.implexa.ai/p2p/settings',
  message: <only present when stub or no-data>,
}
```

## Step 2 — Branch on what's there

### Branch A — real P2P credit pool (most users)

If `is_admin_bridge: false` and `is_enterprise: false`, show:

> ### 💳 Credits & plan
>
> **Plan**: <plan_display> · <plan_status>
> **Remaining**: <credits> / <plan_quota> credits (<100 - usage_pct>% available)
>
> Usage bar (use a 20-char filled/empty visual, e.g. `█████░░░░░░░░░░░░░░░ 25%`)

If `low_balance: true` (under 100 credits left), add a yellow ⚠️ note:

> ⚠️ Running low — heavy workflows like bulk `enrich_contacts` or large-trace `record-skill` sessions may exhaust your balance. Top up at <billing_url>.

If `usage_pct > 80`, suggest considering an upgrade.

### Branch B — admin-bridge stub (enterprise via P2P bridge)

If `is_admin_bridge: true`, show:

> ### 💳 Enterprise account
>
> You're on the enterprise tier (admin-bridged). The credit pool number isn't meaningful at the user level — your org has its own billing.
>
> See **org-level usage** at https://admin.implexa.ai/analytics/usage-tool — that's the real number for enterprise plans.

Use the `message` field from the response verbatim if it's helpful.

### Branch C — no data

If `credits === null` and `is_enterprise: true`, show the `message` field verbatim and offer the `analytics/usage-tool` link.

## Step 3 — Suggest next moves

End with **"What's next?"** — pick prompts contextual to their state. Examples:

**Healthy balance:**
```
- `Find me 10 accounts that match my ICP`
- `Show me my saved messaging agents`
- `Brief me on my next call`
```

**Low balance:**
```
- `Open https://admin.implexa.ai/p2p/billing`
- `Use only free tools — show me what I can do without spending credits`
- `/implexa:setup` (verify everything's working)
```

**Enterprise / bridge:**
```
- `Open https://admin.implexa.ai/analytics/usage-tool`
- `Find me 10 accounts that match my ICP`
- `/implexa:help`
```

## Notes for the model

- This is the most-asked utility — keep the answer under 100 words. Users want a number, not a tutorial.
- For real P2P users with low_balance: true, lead with the warning so they can adjust before kicking off a workflow that might cost more than they have.
- For admin_bridge: don't quote the placeholder credit number (999999 is not user-friendly and meaningless) — just say "enterprise" and route to org usage.
- If `get_credits` itself fails (API key broken, etc.), fall through to `/implexa:setup` for diagnostics — same recovery path as every other skill.
