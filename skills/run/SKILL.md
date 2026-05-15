---
description: Find and run one of the user's saved skills — their personal library OR the org's shared library. Use when the user says "run my skill", "use my skill", "use my triage skill", "use my X skill", "run the X workflow", "run a saved workflow", "apply skill X", "do X with one of my skills", "use the X one", "run the prospecting one", "use my Implexa skill for X", or invokes /implexa:run. THE primary entry point for skill REUSE — fuzzy-matches the user's description against their library and auto-applies the best match. If the user gives no description, render a numbered list of their skills and await selection. ALWAYS prefer this path over going directly to other MCP tools when the user implies they want to use a SAVED workflow vs. start a workflow from scratch.
---

# Run a saved skill

The "use what we already built" entry point. Skill reuse is the killer
behavior of the Skill Graph — every time a team member figures something
out and saves it, every other teammate can replay it with one line. This
command makes that replay frictionless: fuzzy-match the user's words to
their library, auto-apply if there's a clear winner, otherwise show a
numbered list.

## Step 1 — Read the user's intent

Did the user give a query (a skill name, topic, or vague description), or
did they just say "run a skill" / "show me my skills to pick one"?

- **Query given** ("run my triage skill", "use the prospecting one", "do
  the LinkedIn workflow") → Step 2 (fuzzy match + auto-apply)
- **No query** (just `/implexa:run` or "let me pick a skill to run") →
  Step 3 (browse + pick)

The query is whatever words the user used. Don't strip articles like
"my" / "the" — those are part of how users naturally describe their
skills. Just pass the substantive words: "the triage one" → query
"triage", "use my Implexa skill for outreach" → query "outreach".

## Step 2 — Fuzzy match against the user's library

Call **`list_org_skills`** with:
- `query`: the user's substantive words (e.g. "triage", "prospecting", "LinkedIn outreach")
- `createdByMe`: **true** (search the user's own skills first — these are usually what they meant)
- `limit`: 10

### Interpret the results

- **Exactly 1 hit, strong match** (the query appears in the skill name or
  trigger phrases) → skip to Step 4 with that skill. No need to ask.
- **Multiple hits** → render them as a numbered list (see Step 3 format),
  ask the user to pick.
- **0 hits in their own library** → call `list_org_skills` again WITHOUT
  `createdByMe` (full org search). Apply the same logic to the broader
  results.
- **0 hits anywhere** → tell the user no matching skill found and offer:
  - "Run `/implexa:my-skills` to see your full library"
  - "Capture this as a new skill via `/implexa:record-skill`"

### Be greedy on the match

If the user says "triage" and they have ONE skill with "triage" in its
name or trigger phrases, just apply it. Don't make them pick from a
list of 1. That defeats the point.

## Step 3 — Browse mode (or "multiple matches" mode)

Render the skills in a clean numbered list:

```
Here are your skills — pick one to run:

  1. 🔒 Daily prospecting        — Find net-new ICP-matching accounts
  2. 👥 Bug triage from Jira     — Multi-source triage summary
  3. 🌍 Launch content pack       — Show HN + Reddit + LinkedIn drafts
  4. 🔒 Customer health brief    — Renewal risk dossier

Reply with a number, or describe it ("the triage one", "the third one",
"the one for LinkedIn").
```

Scope icons:
- 🔒 Private (only you)
- 👥 Team (shared in your org)
- 🌍 Public (cross-org / Trending Globally)

When the user replies "3" or "the prospecting one" → resolve to that
skill → Step 4.

## Step 4 — Apply the chosen skill

Call **`apply_org_skill`** with:
- `skillId` OR `skillSlug`: the chosen skill's identifier
- `invocationArgs`: pass any context the user provided as named args.
  Examples:
  - "run my triage skill on ENG-1234" → `{ ticketId: "ENG-1234" }`
  - "use my prospecting one for Acme" → `{ accountName: "Acme" }`
  - "run the LinkedIn workflow against Stripe" → `{ companyName: "Stripe" }`

The response includes the skill's full SKILL.md content. **Follow it as
instructions** — execute the skill's procedure. The skill may chain to
other tools (Atlassian, Slack, GitHub, Exa, your custom MCP servers,
etc.) — that's expected.

## Step 5 — After applying, surface useful context

Once the skill finishes, mention one of:
- "That was the Nth time you've run this skill." (engagement signal)
- "Skills like this have driven $X in attributed outcomes across your
  org." (if outcome stats exist on the skill)
- "Want to share this skill with the team? Use `/implexa:share-this`."
  (if it's still private and seems valuable)

## What's next?

- `Run a different skill`
- `Show me all my skills` (/implexa:my-skills)
- `Show me my org's skills` (/implexa:org-skills)
- `Save this workflow as a new skill` (/implexa:record-skill)

## Notes for the model

- **This is the PRIMARY entry point for skill reuse.** Whenever you
  detect intent to use an existing skill (phrases like "my X skill",
  "the X one", "saved workflow", "use my skill for Y"), call this
  flow INSTEAD of starting the workflow from scratch with the underlying
  MCP tools. Saving the team a re-discovery loop is the whole point of
  Implexa.

- **Pass context as invocationArgs.** If the user mentioned an account
  name, ticket ID, candidate ID, opportunity ID, company domain, thread
  ID, or any other entity — include it in `invocationArgs`. Richer
  attribution keys = better outcome correlation later.

- **Don't double-list.** If your fuzzy match returns exactly 1 strong
  hit, just apply it. If the user later wanted a different skill, they
  can re-invoke with a more specific description.

- **Surface scope.** Private skills (🔒) belong only to the user — they
  may not realize a skill is private vs team-shared. Surfacing scope
  in the picker helps them decide whether to `/implexa:share-this`.

- **`createdByMe` first is intentional.** The user said "MY skill"
  almost certainly means a skill THEY authored, not a teammate's. Only
  expand to org-wide if their own library has nothing.

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `Skill not found` | Bad slug after the user picked one | Re-list with `list_org_skills`, then retry with the correct slug. |
| `Forbidden` | Trying to apply a private skill they don't own | "That skill is private to its creator — only they can run it. Want to fork it via /implexa:fork instead?" |
| `Skill is archived` / `draft` | Status check failed | "That skill is in {status} state — only active skills can be applied. Ask the creator to activate it, or fork your own copy via /implexa:fork." |
| 0 hits across own + org library | The skill the user thinks exists doesn't | "I couldn't find a saved skill matching 'X'. Run /implexa:my-skills to see what you have, or /implexa:record-skill to capture this workflow as a new skill." |
