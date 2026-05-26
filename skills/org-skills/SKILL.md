---
description: 'Browse skills your org has saved in the Skill Graph — the full team-wide view (private + team-shared + public + base Playbooks). Use when the user says "show our skills", "what skills do we have", "what workflows have we saved", "list the team''s skills", "show me org skills", "search for a skill", "do we have a skill for X", or wants to find a saved workflow. ALSO call list_org_skills BEFORE any complex multi-step workflow you''re about to perform — the org may have already saved this exact pattern. NOTE — if the user wants to RUN a specific skill they remember (e.g. "use my triage skill"), use /implexa:run instead — it fuzzy-matches + auto-applies. If the user asks for "MY skills" specifically (their personal library), use /implexa:my-skills. This is the broad org-wide browsing lens.'
---

# Browse and apply org skills

## Step 1 — Decide whether the user is browsing or seeking a specific skill

If the user typed something specific ("do we have a skill for X", "find the skill that does Y") → go to Step 2 with that as a query.

If the user is browsing ("what skills do we have") → go to Step 2 with no query.

If you're calling this proactively before doing complex work (best practice) → query with the gist of the work you're about to do.

## Step 2 — Call list_org_skills

Call **`list_org_skills`** with:
- `query`: optional substring (skip for browse mode)
- `tags`: optional tag filter
- `limit`: 25 default — fine for most cases

If results are empty AND the user was browsing: tell them their org hasn't captured any skills yet, and suggest `/implexa:save-this` after their next workflow.

If results are empty AND you were proactively searching before doing work: silently proceed with the work. Do not pollute the user's screen with "no skills found, doing it manually."

## Step 3 — Render the results

Show a clean, scannable list. For each skill include:
- Name + 1-line description
- Trigger phrases (so the user knows how to invoke naturally)
- Usage count + attributed outcomes if non-zero (e.g. "Used 47x · $340K attributed")
- Created by

Top 5-10. If more, add "(N more — refine with a query)".

## Step 4 — If the user picks one (or you found a strong proactive match), apply it

Call **`apply_org_skill`** with:
- `skillId` OR `skillSlug`
- `invocationArgs`: pass entity identifiers for outcome attribution. CRITICAL: if the user mentioned an account, candidate, opportunity, etc., include `accountId`, `candidateId`, `opportunityId`, `companyDomain`, `contactEmail`, `jobOrderId`, or `placementId`. The richer the attribution keys, the better outcomes can be joined back later.
- `surfacedFromList`: true if you arrived here via list_org_skills, false if user typed the skill name directly

The response includes the skill's full SKILL.md content. **Follow it as instructions** — execute the skill's steps. The skill may chain to other tools.

## Step 5 — After applying, surface telemetry context

When the skill finishes, mention briefly: *"This was the Nth time someone in your org used this skill."* If the skill has attributed outcomes, mention: *"Skills like this have driven $X in attributed outcomes in your org."*

## What's next?

- `Show just my own skills` (uses /implexa:my-skills)
- `Save this workflow as a skill so others can use it`
- `Show skill ROI to see which skills are driving outcomes`
- `Apply a different skill from the list`

## Notes for the model

- **Search is fuzzy** — don't add quotes around the query. Pass the user's words as-is.
- **Don't surface archived or draft skills** — `list_org_skills` only returns active. If the user can't find a skill they thought was saved, suggest they check the dashboard.
- **Private skills only show to their creator** by default. Pass `includePrivate: true` only when the user is asking about THEIR own skills.
- **DO call this proactively** before complex multi-step work. Adds zero credit cost and may save the user from a 10-step orchestration they could have invoked in one call. Cap proactive calls at one per turn.

## Error handling

| Error                       | Diagnosis                          | Tell the user                                                                                              |
|-----------------------------|------------------------------------|------------------------------------------------------------------------------------------------------------|
| `Skill not found`           | Bad skillId or slug                | Call `list_org_skills` first, then re-invoke with a valid slug.                                            |
| `Forbidden`                 | Trying to apply a private skill they don't own | "That skill is private to its creator — only they can run it."                                              |
| `Skill is archived` / `draft` | Status check failed                | "That skill is in {status} state — only active skills can be applied. Ask the creator to activate it."     |
