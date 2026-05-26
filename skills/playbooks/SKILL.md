---
description: 'Browse the 30 base "Playbooks" — system-scoped read-only skills that ship with every install across 7 verticals (GTM, Talent Acquisition, Customer Success, Product Engineering, People Ops, Finance, Marketing). Use when the user says "show me the playbooks", "what playbooks does Implexa have", "browse base skills", "what comes built-in", "playbook library", "show me what Implexa ships with", or wants to discover skills before forking them. The discovery surface for the base library — every Playbook can be invoked directly OR forked into the user''s org for customization.'
---

# Browse Playbooks (the base library)

The user wants to see what's built-in. Implexa ships with 30 base Playbooks across 7 verticals — atomic, composite, and outcome tiers. Each one is fully invocable as-is, or forkable for customization.

## Step 1 — List the system Playbooks

Call **`list_org_skills`** with:
- `query`: optional — filter to a specific topic if the user mentioned one
- `tags`: optional — filter to a vertical or tier (e.g. `['gtm']`, `['talent']`, `['composite']`)
- `includePrivate`: false
- `limit`: 50

The Playbooks have `scope: 'system'` and `organizationId: 'system'` — they appear alongside the user's own org skills but are tagged distinctly.

If the user asked for a specific vertical (sales, recruiting, customer success, etc.) → filter by tag.
If they're browsing → show grouped by vertical.

## Step 2 — Render grouped by vertical

Group the results by `tags[0]` (the vertical) and render a clean catalog:

```
🎯 GTM (10 Playbooks)
   • Research a prospect          (atomic)    — 4-6 sentences of context, ready to drop into a cold email
   • Draft a cold email           (atomic)    — 4-sentence outreach in your voice
   • Find decision-makers         (atomic)    — 3-5 budget owners at a target
   • Full account research        (composite) — comprehensive prep for discovery call
   • Pre-call prep                (composite) — one-screen brief from a calendar event
   • Cold outreach sequence       (composite) — 5-touch personalized sequence
   • Account expansion play       (composite) — find new buying centers at existing customers
   • Land the meeting             (outcome)   — end-to-end SDR workflow

🎯 Talent Acquisition (5 Playbooks)
   • Source candidates by skill   (atomic)    — 10-20 ranked candidates
   • Fill this Bullhorn role      (composite) — Bullhorn DB + external + draft submittal
   • Redeploy a candidate         (composite) — find next role for ending engagement
   • Interview prep brief         (composite) — interviewer briefing
   • Daily Bullhorn standup       (outcome)   — book-of-business briefing

🎯 Customer Success (4 Playbooks)
   • ...

🎯 Product Engineering (2 Playbooks)
🎯 People Ops (2 Playbooks)
🎯 Finance / FP&A (2 Playbooks)
🎯 Marketing (3 Playbooks)
```

For each line, include the slug somewhere clickable so the user can pick one to apply or fork.

## Step 3 — Offer the next move

End with:

> *"Three things you can do with any Playbook:*
> 1. *Run it directly — say 'run [slug]' and I'll execute against whatever target you give me*
> 2. *Fork it into your org for customization — say 'fork [slug]'*
> 3. *Demonstrate your version once and I'll save a brand new skill — `/implexa:record-skill`*"*

## Step 4 — Handle the user's choice

If they say "run X" → call **`apply_org_skill`** with skillSlug=X
If they say "fork X" → call **`fork_org_skill`** with sourceSkillId=X (in the org_skills collection, look up by slug)
If they ask "what's the difference between [tier]" — explain:
- **Atomic**: 30-60 second runs, single tool chain, single output
- **Composite**: multi-tool workflows, 2-5 minutes, "saves my whole afternoon" scope
- **Outcome**: end-to-end orchestrations with branching/retry — the hero demos

## What's next?

- `Run a Playbook against my target company`
- `Fork a Playbook so I can customize it for my style`
- `Show me my org's own skills (not just Playbooks)`

## Notes for the model

- **System Playbooks vs org skills**: Playbooks have `scope='system'`, the user's saved skills have `scope='org'` or `'private'`. Both show up in list_org_skills. Distinguish them in the rendering — Playbooks are the base library; org skills are what the team built.
- **Don't dump all 30 unless asked.** Default to grouped/summarized view. If the user wants details on a specific vertical, drill in.
- **Outcome tier = demo material.** When a user asks "what's most impressive", surface the outcome-tier Playbooks first. They're the 30-second screen-recording moments.
- **Forking is the activation.** When a user finds a Playbook they like, encourage forking. A forked Playbook becomes their own skill — discoverable in their org, customizable, attributable.

## Error handling

| Error                              | Diagnosis                       | Tell the user                                                                                                |
|------------------------------------|---------------------------------|---------------------------------------------------------------------------------------------------------------|
| `list_org_skills` returns 0 system Playbooks | Seed script hasn't run yet | Tell user: "Base Playbooks aren't loaded on this backend — your team can run `node scripts/seed-base-playbooks.js --confirm`." |
| User asks for a Playbook that doesn't exist | Bad slug or removed Playbook | Suggest 2-3 closest matches by name.                                                                          |
