---
description: 'Find and run the best-fit AGENT for what the user wants to do. An agent is a runnable, schedulable thing: the user''s own agents (saved + generated), their team''s, and ready-to-run agents from the community catalog (Anthropic, Smithery, ClawHub, Skills.sh, GitHub, agentskills, Cursor, Continue), all ranked together. Two paths: (1) NAMED agent ("run the implexa agent X", "run my X agent", "use the X one") resolves and runs that agent directly, no search narration; (2) DISCOVERY ("find me an agent for X", "implexa find me X", "do I have something for X") searches and offers the best matches. Use when the user says "run the implexa agent X", "run my X agent", "use my X agent", "implexa run X", "find me an agent for X", "implexa, find me X", "do I have an agent for X", "is there an agent that does X", "use the X one", "run a saved agent", or invokes /implexa:run with a description. THE unified entry point for running an existing agent. Their own + team agents apply via apply_org_skill / apply_workflow; community agents apply inline via apply_recommended_skill. Prefer this path over going straight to other MCP tools whenever the user wants to USE an existing agent (vs build a new one from scratch).'
---

# Run an agent

THE single entry point for running an agent the user already has access to: their
own and their team's agents, plus ready-to-run agents from the community catalog,
all ranked against one query.

There are two paths, and the FIRST job is to tell them apart:

- **Named agent** ("run the implexa agent Raw recording to clean cut", "run my
  triage agent", "use the prospecting one") → the user already picked. Resolve
  that one agent and run it. Do NOT narrate a multi-stage search.
- **Discovery** ("find me an agent for cold outreach", "implexa find me X", "do
  I have something for renewals") → search, offer the best matches, let them pick.

Stay quiet while you search. The user does not need a play-by-play of which
backend you queried. Present results, not a search log.

## Step 0, named-agent fast path (do this first)

If the user named a specific agent (by its name, an obvious nickname, or "the X
one" pointing at a known agent), skip the merged search. Resolve and run it:

1. Look it up. Prefer the user's own agents first: call
   `mcp__implexa__list_my_workflows` (their saved + generated agents) and match
   by name/slug. If they clearly mean a team/library agent, use
   `mcp__implexa__list_org_skills` with the name as `query`.
2. **One confident match** → run it directly. First do the Step 4.7 preflight
   (CLI tools / sign-ins / connectors; silent when clean). Then, for a whole-job
   agent (a workflow artifact) use `mcp__implexa__apply_workflow` with its slug;
   for a library agent use `mcp__implexa__apply_org_skill`. Then follow Step 5's
   "execute the agent" rules. No list, no "searching the catalog" narration.
3. **No match in their own/team agents** → tell them honestly in one line, then
   offer the discovery path: "I don't see an agent named X in yours or your
   team's. Want me to look in the community catalog?" Only search on a yes.
4. **Genuinely ambiguous** (two agents could be "the X one") → show just those
   two and let them pick. Don't expand into a full search.

Only fall through to Step 1 when the user did NOT name a specific agent.

## Step 1, read intent (discovery path)

Did the user give a query (a topic or vague description), or did they invoke
`/implexa:run` with no description?

- **Query given** ("find me an agent for cold outreach", "implexa, find me X",
  "is there an agent for hubspot") → Step 2 (parallel query).
- **No query** (just `/implexa:run` or "let me pick an agent to run") → Step 6
  (browse mode, their own agents only).

Don't strip articles like "my" / "the" / "a", those are part of how users
naturally describe what they want. Pass the substantive words as the query:
"find me an agent for cold outreach" gives query "cold outreach", "the triage
one" gives query "triage".

## Step 2, search (run both lookups in parallel, quietly)

Make both calls in the SAME response so they run concurrently. Do NOT wait for
one before starting the other, and do NOT narrate them.

**Call A**, `mcp__implexa__list_org_skills`:
- `query`: the user's substantive words
- `createdByMe`: **false** (search the full library, not just the user's own; a
  teammate's agent is still a match for our purposes)
- `includeUniversal`: **false** (the community catalog covers public agents; this
  avoids double-counting)
- `limit`: 5

**Call B**, `mcp__implexa__recommend_skills_for_context`:
- `messages`: `[<the user's query>]` (just the query, one-element array)
- `topN`: 5
- `minScore`: 0.20

If either lookup errors or times out (>10s), proceed with whatever the other
returned. Never block the user on a slow backend.

ONE call to each backend is the WHOLE search. Do not re-query with sub-phrases or
per-feature splits, the single response already carries everything (matches,
module_candidate, workflow_candidate, recommendation_event_id). Re-calling is the
most common cause of a noisy 10+ tool run for what should be 2-3 calls.

## Step 2.4, whole-job agent (lead with this when one matches)

If `recommend_skills_for_context` returned a `workflow_candidate`, the user's
intent maps to a WHOLE JOB implexa can run end to end and keep running on a
schedule. This is the highest-value match: **LEAD with it**, above everything
else.

1. Render the offer in one honest line, what they get + real proof. Use the
   candidate's fields:
   - `workflow_candidate.workflow.name`, `.outcome`, `.cadence`, `.step_count`
   - proof when present: `run_count` / `scheduled_count` → "N people run this on
     autopilot" / "run N times"
   - the candidate's `pitch` line.
2. On the user's go, run it with **`apply_workflow`** using
   `workflow_candidate.apply_call.args`.
3. In the SAME breath, offer the autopilot, matched to the agent's trigger:
   - **`schedule_call` present (recurring agent)** → "run it now to see it work,
     then it keeps happening and emails you the result". Resolve any unanswered
     config first (`get_workflow_setup` → ask → `save_workflow_setup`), then
     `schedule_skill` with `schedule_call.args`, then
     `mcp__scheduled-tasks__create_scheduled_task` with the returned prompt/cron/tz.
   - **`loop_call` present (watch/until agent)** → this is a LIVE agent, fired by
     a Claude `/loop` session, not a clock. Offer: "run it now, then start it
     live". Call `schedule_skill` with `loop_call.args`; it returns a
     `loopInvocation` string, give it to the user to paste. For `watch` it reacts
     to the event; for `until` it re-runs to convergence. It runs while the
     session is open.
4. The merged list (Step 3) sits BELOW as the simpler à-la-carte agents, if they
   don't want the whole job.

This is also what resurfaces a user's OWN saved/generated agents: the recommender
matches the caller's private agents (scoped to them), so a matching intent
re-offers the whole job they saved, ready to re-run or schedule, not rebuilt by
hand. If there is NO `workflow_candidate`, skip this step.

## Step 2.5, verified-module trust-card (lead with this on build intents)

If `recommend_skills_for_context` returned a `module_candidate` block, the user is
asking to BUILD something that maps to a verified open-source package. LEAD with
it, before the merged list and before you write any implementation from memory:

1. The response's `nextAction` is your directive. Follow it: call
   `mcp__implexa__verify_module` with `module_candidate.suggested_call.args` to
   fetch LIVE trust signals (license, sigstore signed status, CVE count,
   scorecard).
2. Render a compact card, then the `caveat` on its own line:
   ```
   implexa verified: <pkg> <version> · <license> · <signed|declared> · <N CVEs> · scorecard <x>
   caveat: <module_candidate.module.caveat>
   ```
3. The `module_candidate.paired_skill` (an [implexa] entry, the procedure bound to
   the verified module) is your #1 recommendation. The community matches from Step
   3 sit BELOW it as alternatives.
4. On the user's go, apply the paired entry via `apply_recommended_skill` with
   `module_candidate.apply_call.args`.

Do NOT hand-roll the implementation when a verified module is on offer, the whole
point is the user gets code they can trust. If there is NO module_candidate, skip
this step and proceed to the merged list.

## Step 3, merge and rank

Build one unified list of agents:

**Your + team agents (from list_org_skills)**:
- Tag each with `[yours]` if `scope === 'private'` OR it was created by the
  current user.
- Tag with `[team]` if `scope === 'org'`.
- Tag with `[base]` if `scope === 'system'` (a base Playbook).
- These don't carry a numerical score (list_org_skills is a substring filter, not
  a similarity match), but treat them as high-confidence by default: they're
  curated and the user already has access.

**Community agents (from recommend_skills_for_context)**:
- Tag each with the `source` field verbatim: `[anthropic]`, `[smithery]`,
  `[clawhub]`, `[skills-sh]`, `[agentskills]`, `[github]`, `[cursor]`,
  `[continue]`.
- They carry a `score` field (0..1, normalized cosine similarity).

**Ordering rule**:
1. Your + team agents first, ordered by `usageCount` desc when there's more than
   one. The user's own wins on ambiguity.
2. Community agents next, ordered by `score` desc.
3. **Dedupe by slug**: if one of the user's agents has the same slug as a
   community one (they forked it), keep theirs and drop the community copy.
4. **Cap at top 5 total**.

## Step 4, display the merged list

Render the unified list. Voice: lowercase, plain, no em-dashes anywhere (use
commas, periods, colons, parens, regular hyphens).

Example output:

```
here are the best agents for "cold outreach":

1. **prospect research to cold email** [yours]
   your saved agent, run 12 times

2. **draft outreach** [smithery]
   score 0.62, fits because the prompt mentions cold outreach drafting
   source: https://smithery.ai/...

3. **linkedin first touch sequence** [clawhub]
   score 0.54, fits because cold outreach into linkedin contacts
   source: https://clawhub.ai/...

want me to run any of these? reply with a number, or "skip".
```

For your/team entries, show the agent's description (or first 80 chars) in place
of the fit_reason. For community entries, show the score and the `fit_reason`
returned by the recommender.

## Step 4.7, in-session preflight (run this before ANY agent run)

The user is HERE, in a live session, so dependency problems get solved here,
not deferred to a dashboard. Before executing a resolved agent (fast path or
picked from the list), do a quick preflight against its definition. Keep it to
one tool-call round when nothing is missing; never narrate a clean preflight.

**1. CLI tools.** Scan the agent's steps for named toolchains (Remotion, ffmpeg,
Whisper, yt-dlp, gdown, Playwright, ImageMagick; generated agents carry a
"Preflight" step naming exactly what they need). Check the missing-prone ones in
ONE Bash call (`command -v ffmpeg; command -v gdown; ...`). For anything
missing, say so in one line and offer to install it now, using the install
command the step itself documents (brew/npm/pipx). Install only on a yes, then
re-check. The run proceeds once tools resolve.

**2. Account sign-ins (browser work).** If the agent's steps or manifest need
signed-in domains (Drive, GitHub, LinkedIn, ...), a terminal session cannot do
the sign-in. Hand off to the activation card, which can:
`open "implexa://workflows/<slug>/activate"` (the Implexa app's card has
per-account Sign in + Verify buttons against the agents' dedicated workspace
Chrome). Fall back to `https://app.implexa.ai/workflows/<slug>/activate` if the
app is not installed. Tell the user to finish the sign-in there and say "done";
then continue the run. For a SCHEDULED agent you can verify reachability
first via `mcp__implexa__get_connection_status` (scheduledSkillId from
`mcp__implexa__list_scheduled_skills`) and skip the handoff when everything is
already reachable.

**3. Missing MCP connectors.** If a step needs an MCP tool this session does not
have (e.g. Chrome driving via the Claude-in-Chrome tools), name the missing
connector in one line and where to enable it, then offer the fallback: run the
step a different way (fetch instead of browse) or route the run through the
Implexa app. Do not silently degrade.

**4. "Activate now" said in-session.** If the user just built the agent and says
"activate now" / "run it" instead of clicking the activation link: that is
consent. Run the preflight above, run the agent here, and at the end mention
once: "to run it on a schedule or from the dashboard, finish activation:
implexa://workflows/<slug>/activate". Do not block the in-session run on
activation state (activation gates the dashboard/schedule paths, not a live
consented run). The exception stays: a draft/archived TEAM agent is not yours
to run; see Edge cases.

## Step 5, run the chosen agent

When the user picks a number ("3"), names one ("run the draft-outreach one"), or
gives any affirmative ("yes run #2", "go ahead with the linkedin one"), run that
agent. **Route by source**:

**If it's a whole-job agent (a workflow artifact, from list_my_workflows or a
workflow_candidate)**:
- Call `mcp__implexa__apply_workflow` with its slug + any context the user gave.

**If source is `yours`, `team`, or `base`** (any list_org_skills entry):
- Call `mcp__implexa__apply_org_skill` with:
  - `skillId`: the `skillId` from the entry (preferred), OR `skillSlug`: the slug
  - `invocationArgs`: any context the user provided (account names, ticket ids,
    candidates, opportunities, threads, domains)
- The response includes the full agent definition in `content`. Execute it
  immediately against the user's original intent.

**If source is a community catalog name** (`anthropic`, `smithery`, `clawhub`,
`skills.sh`, `agentskills`, `github`, `cursor`, `continue`):
- Call `mcp__implexa__apply_recommended_skill` with:
  - `slug`: the slug from the entry
  - `source`: the source from the entry (verbatim)
  - `recommendation_event_id`: the top-level `recommendation_event_id` returned by
    recommend_skills_for_context (attributes the run back to the surfacing event)
- The response shape is `{ ok, skill_content, skill_metadata,
  execution_instruction, applied_skill_event_id }`. The full definition is in
  `skill_content`. Execute it immediately.

**In every case**: don't summarize the agent, don't paste its definition back at
the user, don't re-ask what they want done. The agent defines its own procedure;
follow it in order. If it needs inputs the user hasn't provided, ask for just
those inputs.

## Step 5.5, CLOSE THE RUN (required — this is what registers it)

A run that produced a deliverable but never recorded itself is invisible: the
dashboard run count does not move and the user thinks nothing happened (a real
complaint). The instant the run finishes, before you move on, close it:

1. **If you ran a whole-job agent via `apply_workflow`** (the usual path): call
   `mcp__implexa__record_workflow_outcome` with that run's `workflow_run_id` and
   `status: "executed"` (add an `outcome` object if you can already see the
   result). This is what flips the attempt to executed and bumps the count. Do
   it even on a partial/failed run — pass the honest status.
2. **If this run came from a desktop run-request** (you got it from
   `get_pending_run_requests`): also call `mcp__implexa__resolve_run_request`
   with its `request_id` and `status: "done"` (and the `run_id` if you have one).
   This clears it from the desktop AND records the run server-side. Never leave a
   handled request pending.

These two calls are cheap and mandatory. Skipping them is the single most common
reason a run "doesn't show up." Make them the last thing you do for the run.

## Step 6, browse mode (no-query path)

If the user invoked `/implexa:run` with no description, fall back to browsing
their own agents. The community catalog needs a query (there's no "show me
everything" surface for the index), so we don't query the recommender here.

Call `mcp__implexa__list_org_skills` with `createdByMe: false`, `limit: 20`.
Render the result as a numbered list with scope icons:

```
here are your agents, pick one to run:

  1. 🔒 daily prospecting,         find net-new ICP-matching accounts
  2. 👥 bug triage from jira,      multi-source triage summary
  3. 🌍 launch content pack,       show HN + reddit + linkedin drafts
  4. 🔒 customer health brief,     renewal risk dossier

reply with a number, or describe it ("the triage one", "the third one").
```

Scope icons:
- 🔒 private (only you)
- 👥 team (shared in your org)
- 🌍 base / public

When the user picks, resolve to that agent and run it via Step 5.

## Step 7, ask for feedback (Like / Dislike / Improve)

After the agent finishes its work, prompt the user for a quick reaction so we can
feed the rank. Use this exact line:

> how was that? **like** (👍), **dislike** (👎), or **improve** (✏️), or just keep going

The id you'll pass through is:
- `aggregated_skill_id` from `skill_metadata.id` (community runs), OR
- `org_skill_id` from the apply_org_skill response (your/team/base),
- `applied_skill_event_id` from whichever apply call you just made (always pass
  this so we can attribute the rating to the specific run).

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
Optionally ask "anything specific?", if the user answers, pass that as
`comment`. Reply briefly: `got it, dropping the rank. try /implexa:suggest for an alternative.`

### improve (edit path)

Ask the user: "what would you change about this agent?", capture their answer as
the comment.

Then call `mcp__implexa__submit_skill_feedback` with:
```json
{ "...": "...", "rating": "improve",
  "comment": "<the user's answer>",
  "applied_skill_event_id": "..." }
```

Then chain into the edit flow: invoke `/implexa:edit-workflow` referencing the
agent the user just ran, with their improvement comment as the starting context.
The edit lands as a new version of the agent, no rebuilding from scratch.

### no response (user just keeps working)

If the user types anything that isn't a clear like/dislike/improve, treat it as
"keep going" and do nothing, silence is the most common path.

## Step 8, surface context (optional, only when relevant)

If the feedback turn ended quickly (user clicked like or skipped), you can
optionally mention ONE of these, keep to ONE line, skip entirely if it doesn't
fit:
- "that was the Nth time this agent ran in your org" (engagement signal)
- "agents like this have driven $X in attributed outcomes" (if outcome stats
  exist)
- "want to share this with the team? use /implexa:share-this" (if it's still
  private and seems valuable)
- "want to fork this community agent into your own? just say 'fork this agent'"
  (only for community runs the user might want to customize)

## Edge cases

| Case | Behavior |
|---|---|
| Both backends return 0 matches | "no agents in yours or the community catalog match that. you could build one (just describe the job), or try a more specific query." |
| Yours returns 0, community returns hits | show the community list only. no [yours] entries. |
| Community returns 0 (min_score not crossed), yours has hits | show yours only, add a one-liner: "no community matches above the relevance threshold for this query." |
| Backend timeout (>10s) on one side | proceed with whatever the other returned. don't block. |
| User asks to run a private agent they don't own (Forbidden) | "that agent is private to its creator. want to fork it? just say 'fork this agent'." |
| apply_recommended_skill returns `ok: false` (agent removed, content empty) | surface the error honestly and offer the entry's source URL as a fallback. |
| Agent is in draft status | "that agent is in draft state, only active ones can be run. ask the creator to activate it, or fork your own copy." |

## Greedy match rule

If the user says "triage" and ONE agent has "triage" in its name or trigger
phrases AND it's the only top-of-list candidate, just run it directly. Don't make
them pick from a list of 1.

"Top-of-list candidate" means: the library returns exactly one substring hit AND
no community match has a notably higher score. When in doubt, render the list and
let the user pick.

## Notes for the model

- **Pass context as invocationArgs.** If the user mentioned an account, ticket id,
  candidate, opportunity, domain, or thread, include it in `invocationArgs` (for
  apply_org_skill) or relay it as the user's working context (for
  apply_recommended_skill / apply_workflow). Attribution keys make outcome
  correlation possible.

- **Source tag is mandatory in display.** Users need to see whether a match is
  their own vs from the community. The tag shapes their expectation: their own
  "just work", community ones may need a tool the current session lacks.

- **Don't query the recommender in browse mode (Step 6).** It expects a query.

- **Don't double-call backends.** One pass through Step 2 is the whole search. If
  the user refines, treat it as a fresh invocation.

- **Voice rules apply to all user-facing output.** Lowercase, plain, no em-dashes
  anywhere. Use commas, periods, colons, parens, or standard hyphens.

## What this command IS NOT

- It is NOT a search box for the ENTIRE community catalog without a query. For
  browsing everything, the dashboard at https://app.implexa.ai/agents is the
  right surface.

- It is NOT a way to view buffered ambient matches. That's `/implexa:suggest`,
  which reads the local pull-buffer the recommender hook wrote silently as the
  user typed.

- It is NOT where you build a new agent from scratch. When nothing matches and the
  user wants something new, describe the job and build it (generate_workflow); to
  save a job you just did by hand as a reusable agent, point them at
  `/implexa:record`.

## Why this is the entry point

Three entry points, clear semantics:

1. **`/implexa:run` (this one)** OR **"implexa, run X"** OR **"do I have an agent
   for X"** → find + run an existing agent, yours and the community, ranked.
2. **`/implexa:suggest`** → pull-buffer of ambient matches that fired silently
   during recent prompts.
3. **`/implexa:record`** → save a multi-step job you just did as a reusable agent.

The "implexa as a verb" claim holds: "implexa, find me X" still routes here. One
mental model, one authoritative answer regardless of phrasing.

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `Skill not found` from apply_org_skill | bad slug after picking | re-list with list_org_skills, retry with the correct slug. |
| `Forbidden` from apply_org_skill | private agent not owned by the caller | "that agent is private to its creator. want to fork it? just say 'fork this agent'." |
| `Skill is archived` / `draft` | status check failed | "that agent is in {status} state. only active ones can be run. ask the creator to activate it, or fork it." |
| `skill not found in the cross-vendor index` from apply_recommended_skill | source row removed | "that agent was removed from {source}. try a different one, or browse the source directly." |
| `skill was indexed without content` | source row has empty content | "no content available for that one. here's the source URL if you want it manually: {source_url}." |
| Both backends 0 matches | nothing matched | "no matches in yours or the community catalog. describe the job and I'll build it, or rephrase the query." |
