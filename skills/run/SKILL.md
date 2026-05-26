---
description: 'Find and run the best-fit skill for what the user wants to do, searching BOTH the user''s personal/org library AND the cross-vendor skill graph (Anthropic, Smithery, ClawHub, Skills.sh, GitHub, agentskills, Cursor, Continue) ranked together. Use when the user says "find me a skill for X", "implexa, find me X", "do I have a skill for X", "is there a skill that does X", "run my X skill", "use my X workflow", "implexa run X", "apply skill X", "find a skill", "search skills", "what skills do I have for X", "use my skill", "run a saved workflow", "use the X one", or invokes /implexa:run with a description. THE unified recommender entry point. Personal/team library matches are tagged [personal] or [team] and apply via apply_org_skill. Cross-vendor matches are tagged [anthropic]/[smithery]/[clawhub]/[skills-sh]/[agentskills]/[github]/[cursor]/[continue] and apply inline via apply_recommended_skill. Both kinds rank against the same query. The user doesn''t need to know which source has what; they ask, they get the best matches. ALWAYS prefer this path over going directly to other MCP tools when the user implies they want to USE an existing skill (vs build a new one from scratch).'
---

# Run a skill (unified recommender)

THE single entry point for skill reuse. When a user types a query, this
skill searches BOTH backends in parallel:

1. their personal + team + org library (the curated skills they and their
   teammates have already captured)
2. the cross-vendor skill graph (252+ skills indexed from Anthropic, Smithery,
   ClawHub, Skills.sh, GitHub, agentskills, Cursor, Continue)

Results merge into one ranked list. Personal matches carry the highest
confidence (the user explicitly opted in to save them). Cross-vendor
matches rank by cosine similarity from the recommender. The user picks
one and we apply it inline, routing to the correct apply tool based on
the chosen entry's source.

This is the architectural unification that resolves the routing collision
discovered during P2.2 smoke test. Claude Code's slash-command intent
classifier routes "implexa, find me X" to /implexa:run regardless of
phrasing, so /implexa:run IS the unified recommender. One mental model,
one entry point.

## Step 1, read intent

Did the user give a query (a skill name, topic, vague description), or did
they invoke /implexa:run with no description?

- **Query given** ("find me a skill for cold outreach", "implexa, find me
  X", "run my triage skill", "use the prospecting one", "is there a
  skill for hubspot integration") → Step 2 (parallel query)
- **No query** (just `/implexa:run` or "let me pick a skill to run") →
  Step 6 (browse mode, personal library only)

Don't strip articles like "my" / "the" / "a", those are part of how users
naturally describe what they want. Pass the substantive words as the query:
"find me a skill for cold outreach" gives query "cold outreach", "the triage
one" gives query "triage", "use my Implexa skill for outreach" gives query
"outreach".

## Step 2, query both backends in parallel

Make both tool calls in the SAME response so they run concurrently. Do
NOT wait for one before starting the other.

**Call A**, `mcp__implexa__list_org_skills`:
- `query`: the user's substantive words
- `createdByMe`: **false** (search the full org library, not just user's
  own. a teammate's skill is still a personal-library match for our
  purposes)
- `includeUniversal`: **false** (we cover public skills via the cross-vendor
  index instead, avoids double-counting)
- `limit`: 5

**Call B**, `mcp__implexa__recommend_skills_for_context`:
- `messages`: `[<the user's query>]` (just the query, one-element array)
- `topN`: 5
- `minScore`: 0.20

If either backend errors or times out (>10s), proceed with whatever the
other returned. Never block the user on a slow backend.

## Step 3, merge and rank

Build a unified list:

**Personal/team matches (from list_org_skills)**:
- Tag each with `[personal]` if `scope === 'private'` OR the skill was
  created by the current user (createdBy matches).
- Tag with `[team]` if `scope === 'org'`.
- Tag with `[system]` if `scope === 'system'` (base Playbook).
- These don't carry a numerical score (list_org_skills is a substring
  filter, not a similarity match), but treat them as high-confidence by
  default because they're curated and the user has access already.

**Cross-vendor matches (from recommend_skills_for_context)**:
- Tag each with the `source` field verbatim: `[anthropic]`, `[smithery]`,
  `[clawhub]`, `[skills-sh]`, `[agentskills]`, `[github]`, `[cursor]`,
  `[continue]`.
- They carry a `score` field (0..1, normalized cosine similarity).

**Ordering rule**:
1. Personal/team matches first (top of the list), ordered by `usageCount`
   desc when there's more than one. The user's own library wins on
   ambiguity.
2. Cross-vendor matches next, ordered by `score` desc.
3. **Dedupe by slug**: if a personal-library skill has the same slug as
   a cross-vendor one (possible if the user forked from the public
   library), keep the personal entry and drop the cross-vendor copy.
4. **Cap at top 5 total**.

## Step 4, display the merged list

Render the unified list. Voice: lowercase, tech-bro, no em-dashes
anywhere (use commas, periods, colons, parens, regular hyphens).

Example output:

```
here are the best matches for "cold outreach":

1. **prospect research to cold email** [personal]
   your saved workflow, used 12 times
   from this org's library

2. **draft outreach** [smithery]
   score 0.62, fits because the prompt mentions cold outreach drafting
   source: https://smithery.ai/...

3. **linkedin first touch sequence** [clawhub]
   score 0.54, fits because cold outreach into linkedin contacts
   source: https://clawhub.ai/...

4. **email warming campaign builder** [anthropic]
   score 0.41, fits because email outreach setup and warming
   source: https://anthropic.com/skills/...

want me to run any of these inline? reply with a number, or "skip".
```

For personal/team entries, show the skill description (or first 80 chars
of it) in place of the fit_reason. For cross-vendor entries, show the
score and the `fit_reason` returned by the recommender.

## Step 5, apply the chosen entry

When the user picks a number ("3"), names one ("run the draft-outreach
one"), or gives any affirmative ("yes apply #2", "go ahead with the
linkedin one"), apply that entry. **Route by source**:

**If source is `personal`, `team`, or `system`** (any list_org_skills
entry):
- Call `mcp__implexa__apply_org_skill` with:
  - `skillId`: the `skillId` from the list_org_skills entry (preferred)
  - OR `skillSlug`: the `slug` if no id is to hand
  - `invocationArgs`: any context the user provided (account names,
    ticket ids, candidates, opportunities, threads, domains)
- The response includes the full SKILL.md in `content`. Execute it
  immediately against the user's original intent.

**If source is one of the aggregator names** (`anthropic`, `smithery`,
`clawhub`, `skills.sh`, `agentskills`, `github`, `cursor`, `continue`):
- Call `mcp__implexa__apply_recommended_skill` with:
  - `slug`: the slug from the recommender entry
  - `source`: the source from the recommender entry (verbatim)
  - `recommendation_event_id`: the top-level `recommendation_event_id`
    returned by recommend_skills_for_context (this attributes the apply
    back to the surfacing event for the install-rate metric)
- The response shape is
  `{ ok, skill_content, skill_metadata, execution_instruction,
  applied_skill_event_id }`. The full SKILL.md body is in
  `skill_content`. Execute it immediately.

**In either case**: don't summarize the skill, don't paste the SKILL.md
back at the user, don't re-ask what they want done. The skill defines
its own 6 components (intent, inputs, procedure, decision points, output
contract, outcome signal). Follow them in order. If the skill needs
inputs the user hasn't provided, ask for just those inputs.

## Step 6, browse mode (no-query path)

If the user invoked `/implexa:run` with no description, fall back to
the personal-library browse. Cross-vendor search needs a query (there's
no "show me everything" surface for a 252-row index), so we don't query
the recommender here.

Call `mcp__implexa__list_org_skills` with `createdByMe: false`, `limit: 20`.
Render the result as a numbered list with scope icons:

```
here are your skills, pick one to run:

  1. 🔒 daily prospecting,         find net-new ICP-matching accounts
  2. 👥 bug triage from jira,      multi-source triage summary
  3. 🌍 launch content pack,       show HN + reddit + linkedin drafts
  4. 🔒 customer health brief,     renewal risk dossier

reply with a number, or describe it ("the triage one", "the third one",
"the one for linkedin").
```

Scope icons:
- 🔒 private (only you)
- 👥 team (shared in your org)
- 🌍 universal / system (public or base Playbook)

When the user picks, resolve to that skill and go to Step 5's
apply_org_skill path.

## Step 7, ask for feedback (Like / Dislike / Improve)

After the skill finishes its work, prompt the user for a quick reaction
so we can feed SkillRank. Use this exact line:

> how was that? **like** (👍), **dislike** (👎), or **improve** (✏️) — or just keep going

The three responses route as follows. The id you'll pass through is:
- `aggregated_skill_id` from `skill_metadata.id` (cross-vendor applies), OR
- `org_skill_id` from the apply_org_skill response (personal/team/system),
- `applied_skill_event_id` from whichever apply call you just made (always
  pass this so we can attribute the rating back to the specific run).

### like (positive signal)

Call `mcp__implexa__submit_skill_feedback` with:
```json
{ "aggregated_skill_id" or "org_skill_id": "...", "rating": "like",
  "applied_skill_event_id": "..." }
```
Then reply briefly: `noted, that helps the rank. keep going.`

### dislike (negative signal)

Call `mcp__implexa__submit_skill_feedback` with:
```json
{ "...": "...", "rating": "dislike", "applied_skill_event_id": "..." }
```
Optionally ask "anything specific?" — if the user answers, pass that as
`comment`. Reply briefly: `got it, dropping the rank. try /implexa:suggest for an alternative.`

### improve (re-record path)

Ask the user: "what would you change about this skill?" — capture their
answer as the comment.

Then call `mcp__implexa__submit_skill_feedback` with:
```json
{ "...": "...", "rating": "improve",
  "comment": "<the user's answer>",
  "applied_skill_event_id": "..." }
```

The tool returns `nextAction` instructing you to chain into the update
flow. Invoke `/implexa:record` (it handles new + post-hoc save + update
existing) referencing the skill the user just ran. The user's
improvement comment becomes the starting context for the re-record
session, which lands on Branch C (update existing via re-record).

### no response (user just keeps working)

If the user types anything that isn't a clear like/dislike/improve, treat
it as "keep going" and do nothing — silence is the most common path.

## Step 8, surface context (optional, only when relevant)

If the feedback turn ended quickly (user clicked like or skipped), you
can optionally mention ONE of these — keep to ONE line, skip entirely
if it doesn't fit:
- "that was the Nth time this skill ran in your org" (engagement signal)
- "skills like this have driven $X in attributed outcomes" (if outcome
  stats exist on the skill)
- "want to share this with the team? use /implexa:share-this" (if it's
  still private and seems valuable)
- "want to fork this cross-vendor skill into your org? just say 'fork
  this skill'" (only for cross-vendor applies the user might want to
  customize, the model routes natural language straight to fork_org_skill)

## Edge cases

| Case | Behavior |
|---|---|
| Both backends return 0 matches | "no skills in your library or in the open ecosystem match that. you could record one via /implexa:record, or try a more specific query." |
| Personal returns 0, aggregator returns hits | show the cross-vendor list only. no [personal] entries. |
| Aggregator returns 0 (min_score not crossed), personal has hits | show personal only, add a one-liner: "no cross-vendor matches above the relevance threshold for this query." |
| Backend timeout (>10s) on one side | proceed with whatever the other returned. don't block. |
| User asks to apply a private skill they don't own (Forbidden from apply_org_skill) | "that skill is private to its creator. want to fork it? just say 'fork this skill' and the model will run fork_org_skill." |
| apply_recommended_skill returns `ok: false` (skill removed, content empty, etc.) | surface the error field honestly and offer the entry's source URL as a fallback. |
| Skill is in draft status | "that skill is in draft state, only active skills can be applied. ask the creator to activate it, or fork your own copy (just say 'fork it')." |

## Greedy match rule

If the user says "triage" and ONE entry has "triage" in its name or
trigger phrases AND it's the only top-of-list candidate, just apply it
directly. Don't make them pick from a list of 1. That defeats the point.

"Top-of-list candidate" means: the personal/team library returns exactly
one substring hit AND no cross-vendor match has a score notably higher.
When in doubt, render the list and let the user pick.

## Notes for the model

- **Pass context as invocationArgs.** If the user mentioned an account,
  ticket id, candidate id, opportunity, domain, thread id, or any other
  entity, include it in `invocationArgs` (for apply_org_skill) or relay
  it as the user's working context (for apply_recommended_skill).
  Attribution keys make outcome correlation downstream possible.

- **Source tag is mandatory in display.** Users need to see whether a
  match comes from their own library vs the open ecosystem. The tag
  shapes their expectation: personal matches "just work" because their
  org already vetted them, cross-vendor matches may need a tool the
  current session doesn't have (apply_org_skill surfaces a
  `requiredTools` hint for that case; apply_recommended_skill surfaces
  the source URL on failure).

- **Don't query the recommender on browse mode (Step 6).** The recommender
  expects a query. With no query there's nothing meaningful to rank
  against the 252-row cross-vendor index. List the personal library
  instead.

- **Don't double-call backends.** One pass through Step 2 is the whole
  search. If the user refines their query, treat that as a fresh
  invocation and rerun Step 2 with the new query.

- **Voice rules apply to all user-facing output.** Lowercase, tech-bro X
  cadence, no em-dashes anywhere. Use commas, periods, colons, parens,
  or standard hyphens.

## What this command IS NOT

- It is NOT a search box for the ENTIRE cross-vendor index without a
  query. There's no "browse all 252 skills" mode here. For that, the
  dashboard at https://app.implexa.ai/skills is the right surface.

- It is NOT a way to view buffered ambient matches. That's
  `/implexa:suggest`, which reads the local pull-buffer the recommender
  hook wrote silently as the user typed prompts.

- It is NOT a skill-recording surface. For capturing a new workflow,
  point the user at `/implexa:record`.

## Why this is the final entry point

Three entry points, clear semantics:

1. **`/implexa:run` (this one)** OR **"implexa, find me X"** OR **"do I
   have a skill for X"** → unified recommender, both sources, ranked.
2. **`/implexa:suggest`** → pull-buffer of ambient matches that fired
   silently during recent prompts.
3. **`/implexa:record`** → capture a new skill from demonstration.

No competing paths. The "implexa as a verb" claim is preserved because
"implexa, find me X" still works (Claude Code's slash-command router
points it here). One mental model. One authoritative answer regardless
of phrasing.

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `Skill not found` from apply_org_skill | bad slug after picking | re-list with list_org_skills, retry with the correct slug. |
| `Forbidden` from apply_org_skill | private skill not owned by the caller | "that skill is private to its creator. want to fork it? just say 'fork this skill'." |
| `Skill is archived` / `draft` | status check failed | "that skill is in {status} state. only active skills can be applied. ask the creator to activate it, or fork it (just say 'fork it')." |
| `skill not found in the cross-vendor index` from apply_recommended_skill | source row was removed | "that skill was removed from {source}. try a different recommendation, or browse the source directly." |
| `skill was indexed without content` from apply_recommended_skill | source row has empty content | "no content available for that one. here's the source URL if you want to install manually: {source_url}." |
| Both backends 0 matches | the query has nothing | "no matches in your library or the open ecosystem. try /implexa:record to capture a new workflow, or rephrase the query." |
