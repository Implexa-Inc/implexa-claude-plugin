---
description: 'Run the user''s morning brief — chains existing skills (standup from yesterday''s commits + daily AI signal) into one terse update. Use when the user says "my morning brief", "run my morning", "morning update", "what''s the deal today", "catch me up", or invokes /implexa:morning. THE primary entry point for orchestrated skill chains — composes multiple existing skills into a single user-facing run via the `orchestrate_skills` MCP tool. Prefer this over running each skill individually when the user wants their daily kickoff.'
---

# Morning brief — chained skill orchestration

Run this each morning. **Default chain** composes two existing skills into one 30-second brief:

1. **standup-from-yesterday-commits** → yesterday's git activity + Jira transitions
2. **daily-ai-skills-pulse** → top AI signal from the last 24h (HN, X, papers)

**Custom chain** (v0.9.1+) — pass skill slugs as args to `/implexa:morning` and the orchestrator runs your chain instead:

```
/implexa:morning standup-from-yesterday-commits hackernews-and-x-comment-drafter aeo-content-plan
```

The arg-supplied chain replaces the default for THIS run only. v0.10.0 will add `--save` to persist a custom default per user.

The orchestrator handles the chain via `orchestrate_skills`. You read each step's returned `content` and execute it like any other skill, then synthesize the outputs into one unified brief.

This is the orchestrator-pattern entry point. Future commands like `/implexa:end-of-day` and `/implexa:do-my-work` follow the same shape.

---

## Step 0 — Parse the chain from slash command args (v0.9.1+)

Inspect the `<command-args>` section of this invocation.

**Case A — no args** (or empty / whitespace-only): use the default chain.

```js
chain = ["standup-from-yesterday-commits", "daily-ai-skills-pulse"];
isCustomChain = false;
```

**Case B — args present**: parse as a space- or comma-separated list of skill slugs. Each token is treated as a kebab-case slug, exact-match resolved by the orchestrator. The chain is the ordered list in arg order.

```js
// /implexa:morning standup-from-yesterday-commits aeo-content-plan
chain = ["standup-from-yesterday-commits", "aeo-content-plan"];
isCustomChain = true;

// /implexa:morning a, b, c   (commas tolerated)
chain = ["a", "b", "c"];
```

**Validation rules:**
- 1 ≤ chain.length ≤ 10 (the orchestrate_skills schema enforces max 10; reject pre-call if user supplied more)
- Each token must match `/^[a-z0-9-]+$/i` (kebab-case slug). If a token has spaces or invalid chars (e.g. natural-language phrases like "morning briefing"), stop and tell the user: "I need exact skill slugs like `standup-from-yesterday-commits`, not natural-language descriptions. To see your library: `/implexa:my-skills`."

**Ambiguous args:** if the args look like natural language ("run my morning skills") rather than a slug list, do NOT silently fall back to default. Stop and ask for clarification: "Did you mean the default chain (no args needed) or specific slugs (pass them space-separated)?"

## Step 1 — Call the orchestrator

Call **`orchestrate_skills`** with:

- `command`: `"morning"` (always; the telemetry label is stable across default + custom chains)
- `chain`: the chain from Step 0 (default OR custom)
- `context`: `{ source: "slash-command", isCustomChain: <bool from Step 0>, rawArgs: "<the original args string, if any>" }` — stored in orchestrations.metadata. The v2 recommender will mine this field to learn user preferences ("ashish always passes these 3 slugs on Mondays") and eventually surface those as `--save`-able defaults.

The tool returns:

```jsonc
{
  "orchestrationId": "uuid",
  "command": "morning",
  "status": "completed" | "partial" | "failed",
  "steps": [
    {
      "order": 1,
      "slug": "standup-from-yesterday-commits",
      "name": "Standup update from yesterday's commits",
      "status": "completed",
      "content": "<SKILL.md body — follow this as instructions>"
    },
    {
      "order": 2,
      "slug": "daily-ai-skills-pulse",
      "name": "...",
      "status": "completed",
      "content": "<SKILL.md body>"
    }
  ],
  "failureReason": null
}
```

If `status === "failed"`, surface the `failureReason` and offer to install the missing skills (see Step 4).

## Step 2 — Execute each step's SKILL.md content in order

Each step's `content` field is the literal SKILL.md body for that skill. **Follow it as instructions** — execute the procedure top to bottom. Make all tool calls (GitHub, Jira, web search, etc.) the body specifies.

Keep per-step outputs in memory; do NOT render them to the user mid-chain. The user wants one synthesized brief at the end, not two separate dumps.

**Skip steps with `status: "skipped"`.** The orchestrator already logged the resolution failure; just continue with the working steps. The user will see a brief note at the end about which steps couldn't run.

## Step 3 — Synthesize one unified brief

Combine the per-step outputs into a single brief in this format:

```
*Yesterday + Today*
• <bullet from standup step — outcome-led, ≤12 words>
• <bullet from standup step>
• <bullet from standup step>

*AI signal worth knowing*
• <top item from daily pulse — link or paper title + 1-line so-what>
• <second item>
• <third item — cap at 3>

*Blockers*
• <from standup output, or "none">
```

**Length cap: 200 words total.** Be terse. Lead with outcomes, not activity. The user is reading this in 30 seconds.

If only one step succeeded (`status: "partial"`), render just that step's section. Add a one-line footer noting the skipped step + why (from the step's `error` field).

## Step 4 — Handle missing-skills case

If `status === "failed"` or both steps came back skipped with "Skill not found", the user hasn't installed the required skills yet. Tell them:

```
Your morning brief needs two skills installed:

  • standup-from-yesterday-commits  (yesterday's git + Jira activity)
  • daily-ai-skills-pulse           (top AI news from the last 24h)

Install them via:
  /implexa:fork standup-from-yesterday-commits
  /implexa:fork daily-ai-skills-pulse

Then re-run /implexa:morning.
```

If only one is missing, fork-suggest just that one and offer to run the remaining step solo via `/implexa:run <slug>`.

## What's next?

- `Set up /implexa:morning to auto-run at 8:55am daily` — via `/implexa:schedule`
- `Show me my recent morning runs` — `app.implexa.ai/runs` (live now) or call `list_scheduled_skills` for the orchestrated-via-scheduler set
- `Swap a step in my morning chain for this run` — re-invoke with `/implexa:morning <slug-1> <slug-2> ...` (v0.9.1+; replaces default chain for this run only)
- `Save a custom default chain` — v0.10.0 will add `--save` flag; for now, persistent customization means editing the local plugin's morning/SKILL.md or asking the v2 recommender once it accumulates data

## Notes for the model

- **One synthesized output, not two.** The user typed one slash command. Don't render the standup and the pulse as two separate blocks with their own headers. Stitch them.
- **Outcome-led bullets.** "Shipped invoice export" beats "Added 4 commits to billing.ts". The standup skill's body already enforces this; preserve the convention through synthesis.
- **Cap AI signal at 3 items.** The daily pulse might return more. Pick the three most relevant to the user's stated focus (or fall back to "most-upvoted" if no focus given).
- **Don't fabricate.** If a step returned an empty payload (weekend, sick day, no AI news), say so plainly: "no commits yesterday." Don't invent activity.
- **Telemetry is automatic.** The `orchestrate_skills` tool logs the orchestrations row + per-step skill_invocations + run karma to each skill's creator. No additional calls needed from this skill.

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `orchestrate_skills` returns `status: "failed"` | Neither skill resolved (likely not installed) | "Your morning brief needs both skills installed. Run `/implexa:fork standup-from-yesterday-commits` and `/implexa:fork daily-ai-skills-pulse`, then retry." |
| `orchestrate_skills` returns `status: "partial"` | One step skipped, one succeeded | Render the succeeded step's section; add a one-line footer: "Skipped: <slug> ({error})". |
| Both steps `completed` but produced empty content | Quiet day (weekend, no activity) | Render the empty state plainly: "No commits yesterday. No notable AI signal in the last 24h. Have a quiet morning." |
| `orchestrate_skills` itself errors (network, auth) | Backend unreachable | "Couldn't reach the orchestrator. Try again, or run each skill manually: `/implexa:run standup-from-yesterday-commits` and `/implexa:run daily-ai-skills-pulse`." |

## What this skill demonstrates

This is the **orchestrator pattern** — one slash command, multiple chained skills, single synthesized output. The pattern generalizes:

- `/implexa:end-of-day` chains a wrap-up + tomorrow-prep chain
- `/implexa:do-my-work` (v3) accepts an open prompt and selects the chain dynamically

**Evolution path:**
- **v0.7.0**: hardcoded chain (default = standup + pulse, baked into this file)
- **v0.9.1** (current): user can override the chain by passing slugs as args; default is still used when no args
- **v0.10.0** (planned): `--save` flag persists a per-user default chain
- **v2.0** (recommender-driven): `orchestrate_skills` queries the v2 recommender for "what does this user run in the morning?" and builds chain from accumulated `orchestrations` history. No args needed; the chain adapts as patterns emerge.
