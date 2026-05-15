---
description: List the skills YOU personally authored — your private library. Use when the user says "show my skills", "list my skills", "what skills have I made", "what have I recorded", "my library", "my workflows", "what did I save", or wants to see ONLY their own captured skills (not the org-wide view). Distinct from /implexa:org-skills, which shows everything visible to your org (team-shared, public, base Playbooks). This is the personal-library lens.
---

# Show my skills (personal library)

## Step 1 — Call list_org_skills with createdByMe: true

Call **`list_org_skills`** with:
- `createdByMe`: **true** (this is the key flag — restricts to skills the user authored)
- `query`: optional substring if the user gave one ("show my prospecting skills" → query: "prospecting")
- `tags`: optional tag filter
- `limit`: 25 default

This excludes:
- Base Playbooks (system-scope) — the user didn't author those
- Skills shared from teammates — those are NOT the user's own work
- Universal/public skills authored by others — not the user's work either

This includes:
- Skills the user recorded via `/implexa:record-skill`
- Skills the user saved via `/implexa:save-this`
- Skills the user forked AND edited (forks count as authored once the user touches them)
- Skills in any scope the user authored (private, org-shared, public)

## Step 2 — Render the results, scope-tagged

Group or label by **scope** so the user sees at a glance how each skill is shared:

- 🔒 **Private** — only you can see/use these
- 👥 **Team** (`org` scope) — visible to everyone in your org
- 🌍 **Public** (`universal` scope) — visible cross-org, listed on Trending Globally

For each skill, include:
- Name + 1-line description
- Scope badge (private/team/public)
- Usage count + attributed outcomes if non-zero (e.g. "Used 47× · $340K attributed")
- Trigger phrases (so the user remembers how to invoke them)
- `status: draft` callout if applicable — drafts need activation to be team-visible

If empty, tell the user: "You haven't authored any skills yet. The fastest way to capture one is `/implexa:record-skill` before your next workflow, or `/implexa:save-this` right after."

## Step 3 — Offer next actions

After listing, surface 2-3 concrete next steps based on what's in the library:

- If the user has only private skills → suggest sharing one with the team via `/implexa:share-this`
- If the user has team skills → suggest making one public to earn the Founding Creator badge
- If any skill has high usage but is still in draft → suggest activating it
- Always offer: "Want to see what your teammates have shared too? Run `/implexa:org-skills`."

## Step 4 — If the user picks one, apply it

Same as `/implexa:org-skills` — call **`apply_org_skill`** with `skillSlug` + invocation args (include attribution keys like `accountId`, `companyDomain`, etc. if applicable).

## What's next?

- `Share one of these skills with my team`
- `Show me what my org has captured`
- `Record a new skill from my next workflow`

## Notes for the model

- **This is the personal library lens.** Don't include org-level skills here unless the user authored them.
- **Forks count as authored from the first edit forward** — Implexa stamps `created_by` to the forker on fork creation, so a fresh fork already qualifies. (See the listOrgSkills service note: "Forks count as 'created by me' because the fork's created_by is set to the forker, not the original author.")
- **Don't auto-suggest deletion of low-usage skills.** Skill usage takes time to build. Only mention archive/delete if the user explicitly asks to clean up.
- **If the user follows up with "now show me the team's" or similar → call `/implexa:org-skills`** instead of re-listing.

## Error handling

| Error | Diagnosis | Tell the user |
|-------|-----------|---------------|
| `Skill not found` | Bad slug after they picked one | Re-list with `list_org_skills`, then retry. |
| empty response | They haven't authored anything yet | "You haven't authored any skills yet. Try `/implexa:record-skill` before your next workflow — it captures every prompt + tool call automatically." |
