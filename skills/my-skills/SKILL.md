---
description: 'Browse the Implexa skill library at any scope. Default is `personal` (skills YOU authored). Pass `team` or `org` to see your team-wide library (everyone''s saved skills). Pass `public` to browse base Playbooks + cross-org public skills. Use when the user says "show my skills", "list my skills", "show our team''s skills", "what skills do we have", "browse Playbooks", "what comes built-in", "what''s in the public library", or invokes /implexa:my-skills with or without a scope. Absorbs the old /implexa:org-skills (now scope=team) and /implexa:playbooks (now scope=public). NOTE — if the user wants to RUN one of these skills (vs. just browse), use /implexa:run instead — that fuzzy-matches against the same library and auto-applies. This is the BROWSING lens.'
---

# Browse the library at a chosen scope

This skill is the unified browsing surface across four lenses. It replaces the old `/implexa:my-skills` (personal only), `/implexa:org-skills` (team-wide), and `/implexa:playbooks` (base library) commands — all three are now branches of this one, picked via a `scope` parameter.

## Step 0 — Parse the scope arg

Inspect `$ARGUMENTS` (the text after `/implexa:my-skills`). The first token is the scope; the remainder, if any, is a free-text query substring.

| arg | scope | what it shows |
|---|---|---|
| (none) or `personal` / `mine` / `me` | **personal** (default) | Skills YOU authored — your private library |
| `team` / `org` / `ours` | **team** | Everyone's saved skills in your org (team-shared + private-to-you + public-from-your-org) |
| `public` / `playbooks` / `library` / `all` | **public** | Base Playbooks + cross-org public skills |
| (anything else) | personal, treat the whole arg as a query | — |

Voice hint: if the user typed natural language ("show me my prospecting skills"), strip articles and use `prospecting` as the query under the default `personal` scope. If they typed "browse our team library", set scope to `team` and query to empty.

## Step 1 — Call list_org_skills, branched by scope

Call **`list_org_skills`** with arguments that differ per scope:

**scope=personal** (default):
```jsonc
{
  "createdByMe":      true,
  "query":            "<optional substring>",
  "limit":            25
}
```
Includes: skills you recorded via `/implexa:record`, skills you saved post-hoc, skills you forked AND edited. Excludes base Playbooks, teammate-shared skills.

**scope=team**:
```jsonc
{
  "createdByMe":      false,
  "includeUniversal": false,
  "query":            "<optional substring>",
  "limit":            25
}
```
Includes: every active skill your org can see — your own + teammates' + base Playbooks (system scope shows here too because the org has access). Excludes public skills from other orgs.

**scope=public**:
```jsonc
{
  "createdByMe":      false,
  "includeUniversal": true,
  "query":            "<optional substring>",
  "tags":             "<optional vertical filter>",
  "limit":            50
}
```
Includes: base Playbooks (`scope: 'system'` — ~30 across GTM / Talent / CS / ProductEng / PeopleOps / Finance / Marketing) + universal skills shared by other orgs.

## Step 2 — Render the results, scope-tagged

For every scope, include for each skill:
- Name + 1-line description
- Scope badge (🔒 private / 👥 team / 🌍 universal / 🧰 system Playbook)
- Usage count + attributed outcomes if non-zero (e.g. "Used 47× · $340K attributed")
- Trigger phrases (so the user knows how to invoke naturally)
- `status: draft` callout where applicable

**scope=personal**: simple flat list, sorted by recency.

**scope=team**: group by created-by (`You`, then teammates alphabetical). System Playbooks at the bottom under `🧰 Base library`.

**scope=public**: group by vertical tag (GTM / Talent / Customer Success / Product Engineering / People Ops / Finance / Marketing). If 30+ Playbooks load, summarize per vertical with counts and let the user drill in.

Cap at top 25 (or 50 for public). If more, add `(N more — refine with a query)`.

Empty-state messages:
- **personal**: "You haven't authored any skills yet. The fastest way to capture one is `/implexa:record` before your next workflow, or right after."
- **team**: "Your org hasn't captured anything yet. Run `/implexa:record` after your next workflow — it'll show up here for the team."
- **public**: "Base Playbooks aren't loaded on this backend yet. Ask Implexa support to run the seed script, or build your own via `/implexa:record`."

## Step 3 — Suggest the next move

After listing, surface 2-3 concrete next steps based on the scope and what's in the library:

- **personal** with only private skills → suggest sharing one via `/implexa:share-this`
- **personal** with team-shared skills → suggest making one public to earn the Founding Creator badge
- **team** → "Want to see what's in the public Playbook library? `/implexa:my-skills public`"
- **public** → "Three things you can do with any Playbook: run it directly (`/implexa:run <slug>`), fork it for customization (just ask: 'fork the X Playbook'), or use `/implexa:record` to build your own version after watching one."

## Step 4 — If the user picks one, apply it

Same path regardless of scope — call **`apply_org_skill`** with `skillId` or `skillSlug` + `invocationArgs`. Include attribution keys (`accountId`, `companyDomain`, `contactEmail`, etc.) if the user mentioned an entity. The response includes the skill's full SKILL.md content — follow it as instructions.

For public scope, optionally offer the fork-first path: if the user wants to use a Playbook repeatedly, suggest forking it (natural language: "fork this into my org") so future runs go through their own customized copy.

## What's next?

- `Show me skills I've authored` — `/implexa:my-skills personal`
- `Show me the team's library` — `/implexa:my-skills team`
- `Browse base Playbooks` — `/implexa:my-skills public`
- `Run a skill — /implexa:run <slug>`
- `Record a new skill — /implexa:record`

## Notes for the model

- **The scope parameter is the new mental model.** Old users will type `/implexa:my-skills` expecting just their personal library — that's the default, behavior preserved. New surface is the `team` / `public` extensions.
- **Forks count as authored from the first edit forward** under `personal` scope — Implexa stamps `created_by` to the forker on fork creation, so a fresh fork already qualifies.
- **DO call this proactively** before complex multi-step work (typically with `scope=team` and a relevant query). Adds zero credit cost and may save the user from a 10-step orchestration they could have invoked in one call. Cap proactive calls at one per turn.
- **Don't surface archived or draft skills** — `list_org_skills` only returns active. If the user can't find a skill they thought was saved, suggest they check the dashboard.
- **Public scope = Playbooks + universal.** Both `scope: 'system'` (base Playbooks) and `scope: 'universal'` (cross-org public) come back when `includeUniversal: true`. Render them clearly distinguished so the user knows what's first-party vs. community-contributed.

## Error handling

| Error | Diagnosis | Tell the user |
|-------|-----------|---------------|
| `Skill not found` | Bad slug after they picked one | Re-list with `list_org_skills`, then retry. |
| empty response (personal) | They haven't authored anything yet | "You haven't authored any skills yet. Try `/implexa:record` before your next workflow." |
| empty response (team) | Org hasn't captured anything | "Your org library is empty. Run `/implexa:record` next time you do a workflow worth saving." |
| empty response (public) | Base Playbooks haven't been seeded | "Base Playbooks aren't loaded — ask Implexa support, or build your own via `/implexa:record`." |
| `Forbidden` on apply (Step 4) | Trying to apply a private skill they don't own | "That skill is private to its creator — only they can run it." |
