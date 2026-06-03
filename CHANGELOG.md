# Changelog

All notable changes to the Implexa Claude Code plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** the plugin is a thin wrapper that pins skills + slash commands and
> points at `@implexa/mcp-server` (npm) which proxies to `core.implexa.ai`.
> Backend tool changes (new tools, fixes to existing tools) ship through the
> backend deploy and propagate to all clients without a plugin release. Only
> changes to skills, slash commands, README, or the npm proxy version pin
> warrant a plugin version bump.

## [0.26.0] - 2026-06-03

Workflows surface in-session. When implexa has a whole WORKFLOW for what you are
doing (not just a skill), the ambient hook now surfaces it once per session with
run + schedule options. Workflows are the lead product, so they break the
ambient silence; ordinary skill matches still buffer quietly for /implexa:suggest.

### Added

- **In-session workflow surfacing.** The recommend hook reads workflow_candidate
  from the recommender response and surfaces it as additionalContext at most once
  per Claude session (with apply_workflow + a schedule hint + the workflow page),
  alongside the routine-watchdog catch-up. Answers "why do I only see skills, not
  workflows, while I work".

## [0.25.0] - 2026-06-03

Edit a workflow by just saying it. New /implexa:edit-workflow skill: "update this
workflow to also look at Google Search Console and edit existing pages" resolves
the target, composes the revised step chain, and calls revise_workflow, which
binds the new steps and either revises the user's own workflow in place or forks
a shared workflow into their copy and re-points their schedules. The next
scheduled run uses the change, no re-scheduling, no prompt edit.

### Added

- **edit-workflow skill (natural-language workflow editing).** Routes "edit/update
  this workflow to do X" to the new backend revise_workflow tool (fork-on-edit +
  rebind via the verify gate + outcome prior + schedule re-point).

## [0.24.0] - 2026-06-03

The /implexa:schedule skill now captures a postRunAction (the publish target) at
schedule time, so a one-line "schedule the seo workflow weekly and publish to my
implexa-website repo" stores the config on the schedule and the routine prompt
stays a thin /run-scheduled shim. Pairs with the S1 backend + run-scheduled
Step 2.6.

### Added

- **schedule skill captures postRunAction.** When the user asks to publish/apply
  a workflow's output to a repo, the skill resolves the repo path and passes
  postRunAction { type: "publish-content", repo, ... } to schedule_skill. Omitted
  otherwise. Improving the workflow later never requires touching the prompt.

## [0.23.0] - 2026-06-03

Post-run action (S1): scheduling can stay a thin shim. The run-scheduled wrapper
now executes a structured post_run_action stored on the schedule, so the routine
prompt is a stable `/run-scheduled <id>` and job logic lives in the workflow, not
in hand-edited prompt prose. Improving a workflow never requires touching the
routine again.

### Added

- **run-scheduled Step 2.6: post-run publish action.** When the payload carries
  a `post_run_action` (v1 type `publish-content`), the wrapper writes the
  workflow deliverable to the configured artifact path and runs the repo's gated
  publisher (`node <repo>/<script> <artifact> [--edit --path <p>] --merge`),
  choosing the new-article vs edit branch from the workflow's chosen action.
  Structured config, not raw shell. Skips gracefully when the repo/script is not
  on the machine.

## [0.22.0] - 2026-06-03

Routine watchdog catch-up (N1 surface B). When a scheduled routine does not run
on schedule, the ambient hook now surfaces a gentle one-line catch-up, at most
once per session, so a silent miss (commonly a local routine that did not fire
while the machine slept) does not go unnoticed.

### Added

- **In-session routine catch-up.** The recommend hook reads the backend's
  routine_alert (attached to recommend_skills_for_context when the caller has
  overdue routines) and surfaces it as additionalContext once per Claude
  session, with the remote-routine upsell. The third notify surface alongside
  the daily digest email and the dashboard overdue badge.

## [0.17.0] - 2026-05-31

Verified-module trust-card surfaces ambiently. When a build prompt matches a
verified open-source module (paired skill + live trust signals), the ambient
hook now breaks its silence to surface the card before the model generates a
dependency choice from memory. Stays silent for ordinary skill matches.

### Added

- **Ambient verified-module trust-card.** The recommend hook now emits the
  module trust-card as additionalContext when the backend returns a
  module_candidate (and only then). Ordinary skill matches still buffer
  silently for /implexa:suggest. This is the "fire before you hand-roll it"
  surface from the modules work.
- **Explicit + run-skill lead with the card.** The "implexa, <query>" hook path
  and the /implexa:run skill now lead with the verified-module card when one is
  present (verify_module for live signals, then the paired skill as an option),
  instead of only listing skill matches.

### Changed

- **Word-count gate 8 -> 3.** The ambient gate was filtering most natural build
  prompts ("add stripe billing", "add magic-link login" are 3-4 words). The
  server-side relevance + relative-gap gates already filter noise, so the cheap
  word pre-filter no longer needs to be this aggressive.
- **Card framing is a recommendation, not a command** (backend nextAction). The
  agent surfaces the verified module as an option and lets the user pick, which
  works with Claude's prompt-injection defense instead of tripping it.

### Fixed

- **Empty sessionId no longer breaks the hook.** A missing session_id in the
  local state file would send an empty sessionId, which the backend rejects
  (min 1 char), killing the hook silently under set -e. The hook now generates
  a fallback session id when one is missing.

## [0.16.0] - 2026-05-27

Consolidate the slash-command surface from 20 to 7 visible commands (plus 1
internal callback). The long tail moves to natural-language invocation;
the underlying MCP tools all stay exposed, so asks like "fork this skill",
"give me my morning brief", "publish my X to ClawHub", "show me skill ROI"
still route correctly without a memorized slash command.

### The final 7 (autocomplete-discoverable)

| command | what it does |
|---|---|
| `/implexa:suggest` | find skills (active search or passive buffer pull) |
| `/implexa:run` | unified recommender across library + cross-vendor graph |
| `/implexa:record` | capture a workflow as a skill — 3 entry intents in one flow |
| `/implexa:my-skills [scope]` | browse libraries — personal (default) / team / org / public |
| `/implexa:schedule` | schedule any skill on a recurrence |
| `/implexa:share-this` | team-gated or public share link |
| `/implexa:help` | command list + your current credit balance |

Plus `/implexa:run-scheduled` internally (the scheduler callback).

### Merges

- `/implexa:save-this` + `/implexa:update-skill` → folded into `/implexa:record`.
  The skill now branches in Phase 0:
  - **Branch A** — new skill via live demonstration (the existing flow)
  - **Branch B** — post-hoc save via `capture_workflow_as_skill` (no demo)
  - **Branch C** — update existing via re-record, finalize with `replacingSkillId`
- `/implexa:org-skills` + `/implexa:playbooks` → folded into `/implexa:my-skills`
  via a `scope` argument:
  - `personal` (default — your authored skills, current behavior)
  - `team` / `org` — full org library (everyone's saved skills + base Playbooks)
  - `public` — base Playbooks + cross-org universal skills
- `/implexa:credits` → folded into `/implexa:help`. Balance + plan tier shown
  at the top of the help page.

### Removed (now natural-language only)

- `/implexa:fork` — say "fork this skill" / "fork the X Playbook into my org"
- `/implexa:morning` — say "give me my morning brief" — orchestrates via `orchestrate_skills`
- `/implexa:skill-roi` — say "show me skill ROI" / "which skills are driving outcomes"
- `/implexa:publish-to-clawhub` — say "publish my X skill to ClawHub"
- `/implexa:get-me-started` — first-run flow now lives in the install script's "next steps" output
- `/implexa:setup` — install script handles setup; if the MCP isn't connected, the user re-runs the installer
- `/implexa:setup-hooks` — same as setup

### Migration

Users who memorized the old commands can either:
- Switch to the new shape (`/implexa:record` instead of `/implexa:record-skill`,
  `/implexa:my-skills team` instead of `/implexa:org-skills`, etc.)
- Or just ask in natural language. The MCP tools the old commands fronted are
  still exposed; the model routes most asks correctly without a slash.

### Updated

- `README.md` — new command catalogue + a "why only 7?" section.
- `scripts/install-user-hooks.sh` — next-steps message now points at
  `/implexa:help` (verification) and `/implexa:record` (first skill).
- `hooks/recommend-on-prompt.sh` — `implexa update` fallback message
  recommends natural-language fork + `/implexa:share-this` instead of the
  removed `/implexa:fork`.

## [0.15.0] - 2026-05-25

SkillRank phase A — data-collection foundation for Implexa's proprietary
multi-signal recommendation algorithm. No UX changes for end users beyond
an install-time consent flow; the work here is plumbing for the moat.

### Why this matters

The current recommender uses semantic match on a single prompt. Replicable
by any team in 2 weeks. NOT defensible. SkillRank adds four more signals
(tool stack overlap, work signature similarity, cohort co-occurrence,
outcome attribution) that compound via cross-vendor data only Implexa
collects. Phase A captures the raw signals NOW so phase B has data to
learn from when the algorithm ships.

### Added

- **Install-time consent flow.** New section in `install-user-hooks.sh`
  prompts for three opt-ins after the API-key step. Defaults reflect the
  privacy framing:
  - `tool_inventory_optin`   default **ON**  (low sensitivity, needed for
    ranking)
  - `outcome_tracking_optin` default **ON**  (needed for outcome attribution)
  - `work_signature_optin`   default **OFF** (strict opt-in for cohort
    matching)
  Press enter to accept defaults. Type `c` to customize. Non-interactive
  installs (curl|bash without a tty) write defaults silently. Saved to
  `~/.claude/plugins/implexa/consent.json` (chmod 600) and mirrored to
  the backend via the new `record_consent` MCP tool.
- **Hook signature collection.** `recommend-on-prompt.sh` now also calls
  `record_work_signature` after a positive match (ambient or explicit),
  when the user has opted into work signatures. Payload includes:
  - `session_id` (always)
  - `installed_tools`: merged from `~/.claude/settings.json` mcpServers,
    `claude_desktop_config.json` mcpServers, and `installed_plugins.json`
    plugins (gated on `tool_inventory_optin`).
  - `applied_skills`: read from `~/.claude/plugins/implexa/recent-applies.json`
    (deduped, last 7 days, gated on `work_signature_optin`).
  - `used_tools`, `prompt_categories`: empty in phase A; PostToolUse
    tracker + prompt classifier ship in phase A.1 / phase B.
  Rate-limited to one write per 5 min per session (the cohort algorithm
  aggregates per-session anyway). Fire-and-forget with 3s timeout so the
  hook never blocks.

### Backend (deploys independently of the plugin)

- New table `user_work_signatures` (migration 0029) with anon_id =
  sha256(user_id || monthly rotating salt). 90-day auto-expiry.
- New columns on `users`: `work_signature_optin`, `tool_inventory_optin`,
  `outcome_tracking_optin`, `optin_recorded_at`.
- New MCP tools: `record_work_signature` (writes signatures, gated on
  opt-in, silent no-op on opt-out) and `record_consent` (persists flags
  to the users table).
- New route `POST /api/v2/skill-outcome-tick` for heuristic outcome
  inference on `applied_skill_events.outcome`. Phase A heuristic:
  active > 5min after apply → completed; session_end < 1min → abandoned;
  error within 30s → errored. Idempotent: first inference wins.

### Privacy posture

- Asymmetric defaults (do not reverse). Marketing line: "google sells
  your data. implexa USES your data, only with permission, and only to
  make YOUR recommendations better."
- Prompts that don't match a skill still discarded server-side (existing
  privacy promise on recommendation_events unchanged).
- `anon_id` rotates monthly via `SKILLRANK_SALT_<YYYYMM>` env var. Old
  signatures stay queryable for cohort matching but cannot be re-linked
  to a current user_id after rotation.
- Defense-in-depth: backend gates writes on `users.work_signature_optin`
  regardless of what the hook sends.

## [0.14.0] - 2026-05-24

P2.3: surface unification. `/implexa:run` is now the single authoritative
recommender entry point, searching BOTH the user's personal/team library
AND the cross-vendor skill graph (Anthropic + Smithery + ClawHub +
Skills.sh + GitHub + agentskills + Cursor + Continue) and ranking them
together in one merged list.

### The architecture this fixes

P2.2 smoke test surfaced an unintended routing collision: Claude Code's
slash-command auto-routing intercepts "implexa, find me X" prompts and
routes them to `/implexa:run` BEFORE the UserPromptSubmit hook fires.
The hook works (manual trace via `bash -x` proves it returns honest,
cross-vendor results with structured JSON), but Claude's intent classifier
matches "find me a skill" against `/implexa:run`'s description and bypasses
the hook entirely. Users got `/implexa:run`'s old single-source output
(their org_skills library only) instead of the dual-mode hook's
cross-vendor results.

P2.3's fix: merge the surfaces. `/implexa:run` now BE the unified
recommender. The routing collision turns from a bug into a feature.
Users get the same authoritative answer whether they say "implexa,
find me X" or "/implexa:run X" or "do I have a skill for X" or any
variant. One mental model. One entry point.

### Changed

- **`skills/run/SKILL.md` full rewrite.** The skill now instructs Claude
  to call BOTH `mcp__implexa__list_org_skills` AND
  `mcp__implexa__recommend_skills_for_context` in parallel on every
  query, merge the results, dedupe by slug (personal wins ties), and
  render a single ranked list capped at 5 entries.
- **Source tags in display.** Every entry in the merged list carries
  a tag showing where it came from: `[personal]`, `[team]`, `[system]`
  for library entries; `[anthropic]`, `[smithery]`, `[clawhub]`,
  `[skills-sh]`, `[agentskills]`, `[github]`, `[cursor]`, `[continue]`
  for cross-vendor entries.
- **Routing on apply.** When the user picks a number, the skill routes
  to `apply_org_skill` for personal/team/system entries OR to
  `apply_recommended_skill` for any of the cross-vendor sources, based
  on the chosen entry's tag. The model never has to "decide" which
  applier to call, it just reads the source field off the picked entry.
- **Trigger phrase coverage broadened.** The frontmatter description
  now lists phrasings that previously routed through the dual-mode hook
  ("find me a skill for X", "implexa, find me X", "do I have a skill
  for X", "is there a skill that does X") alongside the original
  /implexa:run trigger phrases. This is intentional, Claude's intent
  classifier should route ALL these phrasings to this single entry point.
- **Browse mode (no-query invocation) preserved.** When the user invokes
  `/implexa:run` with no description, the skill still falls back to
  the personal-library numbered browse (Step 6). Cross-vendor search
  needs a query (no "show all 252 skills" mode), so the recommender is
  not called on this path.

### Compatibility

- **Ambient mode unchanged.** The UserPromptSubmit hook still buffers
  cross-vendor matches silently into the local pull-buffer at
  `~/.claude/plugins/implexa/recent-recommendations.json`.
  `/implexa:suggest` still retrieves the buffer on demand.
- **Explicit-mode hook code path preserved.** The hook's explicit-mode
  branch ("implexa, find me X" → emit additionalContext) stays in place.
  On Claude Code, slash-command routing intercepts before
  UserPromptSubmit fires, so the explicit-mode branch is effectively
  dead code today. It's left in for future-proofing against runtimes
  where UserPromptSubmit fires before slash routing (Codex, Cursor, or
  any agent client that surfaces our plugin without slash-command
  interception).
- **No backend schema changes.** Both MCP tools used by the merged
  flow already exist:
  - `mcp__implexa__list_org_skills` (existing)
  - `mcp__implexa__recommend_skills_for_context` (shipped in P2 alpha)
  - `mcp__implexa__apply_org_skill` (existing)
  - `mcp__implexa__apply_recommended_skill` (shipped in P2.2)
- **No new migrations.** All required tables (`org_skills`,
  `aggregated_skills`, `recommendation_events`, `applied_skill_events`)
  are already in place from earlier migrations 0001 through 0028.

### Privacy (unchanged)

- The `recommend_skills_for_context` server-side `_shouldRetain` gate
  still discards prompts that don't match a skill. No row in
  `recommendation_events`. No log of the prompt body.
- `list_org_skills` is a regular library lookup, no telemetry implications.

### Migration

For users on v0.13.x:
1. Reinstall via `bash scripts/install-user-hooks.sh` from the plugin repo.
   Cache path moves from `~/.claude/plugins/cache/implexa/implexa/0.13.0/`
   to `0.14.0/`.
2. Fix `~/.claude/implexa.env` IMPLEXA_API_URL back to localhost or prod
   if install reset it.
3. Restart Claude Code fully (Cmd-Q on Mac).
4. Next time you type "implexa, find me a skill for X" OR
   "/implexa:run X" OR "do I have a skill for X", you should see a
   merged list with source tags.

No data migration needed.

## [0.13.0] - 2026-05-24

P2.2: the wedge. Inline-apply for ambient recommendations. The user sees a
recommendation, says "yes, run it", and the right SKILL.md gets fetched
from the cross-vendor index and executed inline in the same turn. No
download. No install. No leaving the chat.

### The pitch made real

Before P2.2 the recommender surface ended at "here's a URL, go install it."
That's the same experience as Smithery + ClawHub + Skills.sh. We add nothing.
Now the loop closes: surface, ask, apply. Nobody else does this. This is the
moat the company is built on.

### Added

- **Plugin-side: apply-inline framing** in `hooks/recommend-on-prompt.sh`
  for all three explicit-invocation paths (`implexa, <query>`, `implexa run
  <slug>`, `implexa suggest`/`implexa what`). The `additionalContext`
  now carries explicit instructions: when the user says yes / picks a number /
  affirms, the model calls `apply_recommended_skill` directly with the
  `slug` + `source` + `recommendation_event_id` from the chosen entry,
  receives the SKILL.md body inline, and executes it against the user's
  current request without summarizing or re-asking.
- **`implexa run <slug>` decision rule**: when the resolution is
  unambiguous (single candidate OR top-1 score notably ahead OR exact slug
  match), the model is instructed to apply directly without a confirmation
  roundtrip — the user already opted in by typing `implexa run`. Multiple
  ambiguous candidates still prompt for disambiguation.
- **`/implexa:suggest` Step 4 update**: the previous "if the tool isn't
  registered yet, point at the source URL" branch is gone; `apply_recommended
  _skill` is now live. The step now describes the full apply flow including
  the response shape `{ ok, skill_content, skill_metadata, execution_
  instruction, applied_skill_event_id }` and the error-fallback behavior
  when the source row is missing or empty.

### Backend dependency (ships in the same release window)

- New MCP tool `apply_recommended_skill` in the Implexa backend. Zod schema
  (the 43b7089 lesson stands). Takes `slug`, `source`, optional
  `recommendation_event_id`, optional `session_id`. Looks up the canonical
  row in `aggregated_skills` filtered to `is_active = true`. Returns the
  full SKILL.md body in `skill_content` plus metadata (name, slug, source,
  source_url, description, author, contributor_attribution) and an
  `execution_instruction` that tells the model to execute the skill
  end-to-end without re-summarizing.
- Side effects on the apply path: patches `recommendation_events.ran_slug`
  + `resolved_at` when an event id is provided (closes the surfacing-to-
  action loop for the install-rate metric), and inserts a row in
  `applied_skill_events` (new migration 0028) for the conversion-rate
  metric and as the substrate for P3 run-trace capture. Both side effects
  are log-don't-throw — DB failures never block returning the skill to
  the model.
- Migration 0028 (`applied_skill_events`): one row per inline apply.
  Carries `user_id`, `session_id`, `recommendation_event_id` (nullable —
  direct-apply paths skip the surfacing event), `aggregated_skill_id`,
  denormalized `slug` + `source` (survive source-row deletion), plus
  pre-baked P3+ columns (`outcome`, `trace_summary`, `diverged_from_
  canonical`, `contributed_back`) so P3 run-trace work doesn't need
  another schema migration. RLS is deny-all for anon and authenticated;
  service-role-only writes.

### Why this version is a minor bump, not a patch

`apply_recommended_skill` is a new MCP tool and a new model-facing instruction
surface, not a fix to existing behavior. The user-visible affordance shifts
from "here's a URL" to "let me run it for you", which is a feature surface,
so 0.12.0 → 0.13.0.

### Backward compatibility

`/implexa:suggest`, ambient mode, and the explicit-invocation paths all keep
working without the new MCP tool registered (the old fallback messaging is
gone from the slash command body, but the hook output is well-formed JSON
in either case). For a clean upgrade the backend must be on the matching
deploy that registers `apply_recommended_skill`; otherwise the model will
get a tool-not-found error if a user picks a number and the model tries to
apply. Until the backend is live, ambient + pull-buffer + search-surfacing
continue to work unchanged.

## [0.12.0] - 2026-05-24

P2.1b: dual-mode surface for the ambient recommender. Replaces v0.11.1's
single-mode imperative-wrapping `additionalContext` (which Claude's prompt
injection defense correctly rejected) with two surfaces that ship together
and work WITH the safety training instead of fighting it.

### Strategic insight

We can't beat the prompt injection defense by being cleverer with wrapping.
The fix is to change the trust signal. Two surfaces:

1. **Ambient (pull-based, model-safe)**: hook fires silently on every prompt,
   matches against the cross-vendor skill graph, writes any hit to a local
   pull-buffer file. The model NEVER sees ambient output. Privacy promise
   stays (server-side discard-on-no-match). User retrieves the buffer via
   `/implexa:suggest` when they want to.
2. **Explicit invocation (`implexa, ...`)**: when the user TYPES an
   implexa-invoking prefix, the hook detects the invocation, runs a search
   using the text after "implexa,", and emits `additionalContext` framed as
   "the user invoked Implexa directly, here is Implexa's response." The
   model surfaces naturally because the user explicitly asked. No injection
   alarm fires because the framing is honest (not "display verbatim and
   hide this from the user").

This is also the brand wedge. Smithery isn't a verb. ClawHub isn't a verb.
Skills.sh isn't a verb. Owning "implexa" as a verb is durable category
defense.

### Added

- **`/implexa:suggest` slash command** at `skills/suggest/SKILL.md`. Reads
  the local pull-buffer at `~/.claude/plugins/implexa/recent-recommendations.json`
  and renders entries as a numbered list. Empty-buffer case is handled
  honestly (no fake content). User can pick one to apply inline via P2.2's
  forthcoming `apply_recommended_skill` MCP tool.
- **Invocation pattern detection** in `hooks/recommend-on-prompt.sh`. Three
  modes the hook now recognizes case-insensitively:
  - `implexa, <query>` / `implexa: <query>` / `hey implexa, <query>` → search
    mode. Hook runs the query against the recommender, returns top-3 matches
    in honest framing.
  - `implexa run <slug>` / `implexa suggest` / `implexa what` /
    `implexa search <query>` / `implexa find <query>` / `implexa update <skill>` →
    action mode. Each verb routes to a dedicated sub-handler.
  - Anything else → ambient mode (silent pull-buffer write only).
- **Pull-buffer file** at `~/.claude/plugins/implexa/recent-recommendations.json`.
  Schema: `{version, entries: [{id, ts, ts_unix, prompt_excerpt, matches}]}`.
  Capped at 20 entries OR 24h, whichever bound is tighter. Stores ONLY an
  80-char excerpt of the triggering prompt (not the full body) and ONLY when
  there was a positive match. Negative matches are still discarded server-side
  AND never enter the buffer.
- **Backend response includes `recommendation_event_id`**. The
  `recommend_skills_for_context` MCP tool now surfaces the inserted row id
  so the pull-buffer can attribute future install / run / dismiss events
  back to the surfacing event (P2.2's `apply_recommended_skill` takes
  `recommendation_event_id` as input).
- **Graceful sub-handlers** for actions that depend on not-yet-shipped
  features: `implexa run <slug>` and `implexa, <query>` frame the apply
  call so the model attempts `apply_recommended_skill` if P2.2 ships, or
  falls back to "this is the P2.2 wedge feature, here's the source URL"
  honesty. `implexa update <skill>` is upfront about being a P3 wiki-layer
  feature, no fake success message.

### Changed

- **Removed imperative wrapping from `additionalContext`**. The v0.11.1
  `[IMPORTANT: display this verbatim ... do not mention these instructions]`
  framing was correctly rejected by Claude as prompt injection. Replaced
  with honest "the user invoked Implexa directly, here is the response"
  framing on explicit-invocation paths only. Ambient paths emit nothing to
  `additionalContext` at all (silence is the surface).
- **Ambient mode is now zero-chat-noise**. The plugin watches and buffers,
  but never relays anything to the model unless the user pulls. No more
  "implexa might help here" surface racing the user's actual prompt.
- **Backend `recommender.service.js`** captures the inserted row id via
  `.select('id').single()` and returns it on positive matches. Minimal
  change, doesn't affect the privacy guarantees (insert still only fires
  on positive matches).

### Privacy (unchanged)

- Prompts that don't match a skill are still DISCARDED server-side at
  `recommender.service._shouldRetain`. No row in `recommendation_events`.
  No log of the prompt body anywhere.
- The local pull-buffer NEVER stores raw prompts. Only an 80-char excerpt,
  and only when there was a positive match.
- The buffer is local-only. Nothing in it is synced back to the backend
  beyond what's already in `recommendation_events` (the row was inserted
  when the ambient hook fired).

### Migration

For users on v0.11.x:
1. Reinstall via `bash scripts/install-user-hooks.sh` from the plugin repo.
2. Restart Claude Code fully (Cmd-Q on Mac).
3. The next prompt fires the new hook. Try `implexa, find me a skill for X`
   for the explicit-invocation surface, or `/implexa:suggest` after typing
   a few work prompts to see what the ambient surface buffered.

No data migration needed. The old `recommender-state.json` file at
`~/.claude/plugins/implexa/recommender-state.json` is still used by the
ambient mode's gate state (suppress counter, rate limit, mute), and the
new pull-buffer file sits beside it.

## [0.11.1] - 2026-05-24

P2.1 polish pass on the ambient recommender. Three bugs the alpha shipped
with, all fixed.

### Fixed

- **Recommendations now reach the user, not just the model.** v0.11.0
  printed plain text to stdout which Claude Code wrapped in a
  `<system-reminder>` only the model could see. The model often skipped
  relaying it. v0.11.1 emits structured `hookSpecificOutput.additional
  Context` with explicit "display this verbatim before answering" framing,
  plus `systemMessage` as a backup for surfaces that render it. The hook
  contract has no field that prints directly to user-visible chat, so the
  imperative wrapper is what makes the model reliably surface the rec.
- **False positives from negation patterns suppressed.** Haiku occasionally
  generates fit_reasons like "not creating social content for platforms"
  or "user is asking about X not Y" while still returning the match. The
  recommender now scans the fit_reason post-Haiku for negation markers
  ("not a fit", ", not creating", "isn't relevant", contrastive "X not Y")
  and drops the match before insert. Rejected matches do not log,
  preserving the discard-on-no-match privacy promise.
- **Single absolute threshold replaced with relative gap gate.** The old
  0.72 default was sized for a 5k+ index where real top scores cluster
  higher. With the current 252-row smoke index, real top scores sit in
  0.33-0.40 and 0.72 returned zero hits. Dropping it to 0.25 let false
  positives through. New gate: surface iff
  `top1 >= 0.40` (high-confidence single match) OR
  `top1 >= 0.30 AND top1-top2 >= 0.05` (top1 clearly dominates).
  `RECOMMENDER_MIN_SCORE` is now a hard floor (default 0.20). Add
  `RECOMMENDER_HIGH_CONF`, `RECOMMENDER_GAP_BASE`, `RECOMMENDER_GAP_DELTA`
  to tune surfacing density across index sizes.

### Added

- Debug logging in `hooks/recommend-on-prompt.sh` now produces structured
  `{ts, gate, decision, reason}` lines at every gate decision (word_count,
  mute, suppress_counter, rate_limit, http status, match outcome).
  Opt-in via `IMPLEXA_HOOK_DEBUG=1` in `~/.claude/implexa.env` or your
  shell. Off by default. Captures HTTP status code on non-200 responses
  so flaky backend states attribute correctly.
- `scripts/test-recommender-gates.js` — 25 unit tests covering both gates
  in isolation. Run with `node scripts/test-recommender-gates.js`.

## [0.11.0] - 2026-05-24

Ships the ambient skill recommender (P2). Implexa now watches every prompt
you type in Claude Code and surfaces ONE relevant skill mid-task when it
finds a match in the cross-vendor index. Push-based, not pull-based. No
slash command to remember, no "recommend" mode to enable. Installed once,
fires forever (until you mute it).

### What's new

- New plugin-shipped hook `hooks/recommend-on-prompt.sh` (UserPromptSubmit).
- New install-time consent prompt (opt-in, blocks on Enter, skippable).
- New backend MCP tool `recommend_skills_for_context` (Zod schema).
- New backend service entry point `recommendForContext` over the
  aggregated_skills index (P1 substrate). Semantic match, top-N, parallel
  Haiku fit-reason generation.
- New migration `0026_recommendation_events.sql` for the observational
  substrate. Only positive matches insert rows.

### Privacy: discard-on-no-match

This is the marketing promise, made source-of-truth at the code layer:

- Prompts that produce a recommendation: retained for ranking improvement.
- Prompts that don't match a skill: discarded, never logged.

The retain gate (`_shouldRetain` in `recommender.service.js`) is the ONE
place that decides whether a prompt crosses from fire-and-forget into
persisted. No row in `recommendation_events` = no log = the prompt is
forgotten the moment the HTTP request closes.

### Client-side noise control

The hook is fail-quiet by design. Five gates suppress surfaces:

1. Prompts under 8 words are filtered locally (no API call at all).
2. Sessions in muted-state never fire.
3. After a no-match, the backend hints a suppression counter (default 10
   prompts) that the hook honors locally.
4. Per-fire 90s minimum cool-down.
5. Per-slug 30-minute cool-down (we don't suggest the same skill twice in
   a half-hour window).

Three consecutive dismissals surface a one-tap mute affordance.

### Why this matters

Nobody has shipped ambient + push-based + cross-vendor + already-not-
installed yet. Skyll is pull. mcp-skillset is on-demand. Anthropic's
auto-trigger only fires on skills you already have. The whitespace is
this exact shape, and the privacy posture is part of the moat.

## [0.10.1] — 2026-05-21

Raises `MCP_TOOL_TIMEOUT` from 180s to 300s in the install script.

### Why
v0.6.1 introduced the 180s timeout fix based on the observed 90s ceiling
for normal save flows. In practice the **re-record-into-existing-skill**
merge (Haiku rewrites a 200+ line skill + reconciles a 50+ call new
demonstration trace into one updated SKILL.md) routinely takes 180-250s.

This is the same cosmetic -32001 timeout v0.6.1 was meant to eliminate.
Finalize is idempotent so retries succeed, but the timeout banner still
flashes and reads as a real error to users. Bumping to 300s eliminates
the symptom for typical re-record cases without making truly-hung calls
invisible.

### Changed
- `scripts/install-user-hooks.sh` — TIMEOUT_TARGET 180000 → 300000.
  Same idempotent jq patch (never downgrades a user-set higher value;
  catches and warns if jq fails).

### Backend
No changes. Backend already supports any timeout; the cap was a client-
side knob from the start (see anthropics/claude-code#43791 + #22542).

### Known separate issue (NOT fixed in this release)
When the re-record merge succeeds via retry-on-idempotent, the existing
skill's `version` field doesn't always bump. The `updated_at` moves but
`version` stays put. Symptom: user can't tell the new SKILL.md content
apart from the old version in the dashboard, and rollback semantics are
ambiguous. Bug surfaced 2026-05-21 on `x-shitposting-implexaai-hourly`
v5 re-record. Defer to a separate investigation; not blocking the
timeout fix.

## [0.10.0] — 2026-05-20

Adds **`/implexa:publish-to-clawhub`** — a new slash command that wraps the
5-step manual ClawHub publish workflow (whoami → fetch SKILL.md → stage →
clawhub publish → return URL) into one shot. Defaults version to `0.1.0`
for first publish or auto-increments patch via `clawhub inspect` for
re-publishes. Defaults tags to the skill's existing tags. Defaults owner
to the user's `clawhub whoami` handle. Prompts for a `--clawscan-note`
only when the skill uses Chrome MCP / browser-control / unusual MCPs.
Rejects org/private scoped skills (ClawHub is public-only). Supports
`--dry-run` for testing arg parsing without burning a version number.

Backed by a new `get_skill_content` MCP tool that returns the full
SKILL.md body for one slug (distinct from `list_org_skills`, which omits
content for payload size).

### Added

- `/implexa:publish-to-clawhub <slug> [--version --tags --changelog --clawscan-note --owner --dry-run]`
- `get_skill_content` MCP tool (backend) — fetches one skill's full content + metadata

## [0.9.1] — 2026-05-20

Adds **dynamic chain support** to `/implexa:morning`. Users can now pass
skill slugs as args to override the hardcoded default chain for a single
run:

```
/implexa:morning standup-from-yesterday-commits aeo-content-plan hackernews-and-x-comment-drafter
```

If no args supplied, the existing default (standup + pulse) runs. Bridges
v0.7.0's hardcoded chain to v2.0's recommender-driven chain selection
without a backend change — `orchestrate_skills` already accepts any
1-10 slug chain, the slash command was just hardcoding it.

### Changed
- `/implexa:morning` SKILL.md adds Step 0 (parse args). Validates kebab-case
  slugs, rejects natural-language phrases with a clarifying prompt, enforces
  the 10-slug max. Falls back to default chain when no args supplied.
- Step 1's `orchestrate_skills` call now uses the parsed chain instead of
  the hardcoded list. Adds `context.isCustomChain` + `context.rawArgs` to
  the orchestrations row so the v2 recommender can later mine user
  preferences ("ashish always passes these 3 slugs on Mondays").
- "What's next?" + "What this skill demonstrates" sections rewritten to
  surface the evolution path: v0.7.0 hardcoded → v0.9.1 args → v0.10.0
  --save flag → v2.0 recommender-driven.

### Why
Yesterday user asked: "can I say `/implexa:morning` and then say run X, Y, Z
skills?" Today the answer is yes — pass them as args. v0.9.1 is the
30-minute bridge between v0.7.0's static chain and v2.0's recommender-
driven chain. Same backend tool, same telemetry, just a UX unlock.

### Backend
No changes. `orchestrate_skills` already supports any chain. This was
purely a slash command body update.

## [0.9.0] — 2026-05-20

Closes the CLI-user capability gap on schedule management. Until now, users
on Claude Code without a browser tab had to load app.implexa.ai/scheduled
to pause / resume / delete a schedule. v0.8.1's `/implexa:schedule` SKILL.md
even promised the MCP path with a "v2; for now, dashboard /scheduled has
the toggle" hedge. This is that v2.

### Added (backend — propagates to all clients without a plugin release)
- **`pause_scheduled_skill`** — flip a schedule's status to paused. The
  cron task at Claude Code's runtime keeps firing, but the wrapper short-
  circuits via get_scheduled_skill_payload. Idempotent.
- **`resume_scheduled_skill`** — flip back to active. Also accepts `failed`
  rows for best-effort recovery (next fire will re-attempt naturally; if
  the underlying issue isn't fixed, it'll flip back to failed).
- **`delete_scheduled_skill`** — hard-delete the manifest. Historical
  skill_runs survive (FK is ON DELETE SET NULL — output still at /runs).
  Does NOT tear down Claude Code's scheduled-task; documented in
  nextAction so the user can clean up via the sidebar.
- **`list_scheduled_skills`** — list the caller's schedules with
  humanizedSchedule (natural prose from cron) + nextRunInfo + per-run
  telemetry. Filters: includePaused (default true), includeFailed
  (default false), limit (default 50, max 100).
- **`cron-parser.nextFireApprox(cron, tz)`** — approximate next-fire
  helper for management readbacks. Handles the same shapes humanizeCron
  recognizes; falls back to raw cron echo otherwise.

### Changed (plugin)
- `/implexa:schedule` SKILL.md "What's next?" section now advertises the
  four new MCP tools as the primary management path. Dashboard still
  documented as the visual alternative.

### Why
Yesterday's v0.8.1 promised the v2 MCP path with a placeholder. Users
asked for it the same day. Service methods (updateScheduledSkill,
deleteScheduledSkill, listForUser) already existed — this release just
exposes them via MCP with Zod schemas (per the v0.8.1 outage lesson;
JSON Schema breaks prod, Zod is mandatory). No new business logic.

### Tested
- `scripts/smoke-scheduler-management.js` — 8 branches: create → pause →
  resume → list → delete; idempotent pause; idempotent resume; delete
  non-existent. Plus MCP `tools/list` registry assertion (catches the
  Zod-vs-JSON-Schema bug class).

## [0.8.3] — 2026-05-20

Closes two parser/UX defects surfaced by the v0.8.1 validation report.

### Changed
- `/implexa:schedule` SKILL.md now advertises two additional schedule
  patterns its parser already accepts (and previously didn't):
  - `"every 2 hours"` (any N from 1-23)
  - `"every 3 days"` (any N from 1-30, runs at midnight in the schedule's tz)
- Raw cron passthrough now reverse-humanizes to natural prose in the
  user-facing confirmation. Before: "Scheduled X cron \`0 \*/2 \* \* \*\`."
  After: "Scheduled X every 2 hours." Recognizes hourly/N-minute/N-hour/
  N-day patterns, single-time-recurring (daily, weekday, single-weekday,
  Mon-Fri range), and monthly-on-Nth.

### Why
v0.8.1's own validation brief recommended "every 2 hours" as the test
cadence. The parser rejected it. Embarrassing doc-tells-you-broken-input
bug; fixed here. The reverse-humanize sister fix means power-users who
type raw cron still get clean readback copy.

### Backend
- `src/lib/cron-parser.js` — added `every N hours` (1-23) and `every N days`
  (1-30) patterns; added `humanizeCron(cron)` helper that recognizes 6
  common cron shapes and returns natural prose. Falls back to the raw
  cron echo for unknown shapes (e.g. multi-value lists, comma sets).
- 11 new smoke cases pre-push, all green.

## [0.8.2] — 2026-05-20

Bundles scheduling into `/implexa:record-skill`. After a SKILL.md is saved,
the flow now presents 4 domain-aware cadence recommendations + a skip
option. If the user picks one, `schedule_skill` + `create_scheduled_task`
fire inline; if they skip, existing behavior. Closes the awareness gap
where ~95% of saved skills never got scheduled because users didn't know
`/implexa:schedule` existed.

### Changed
- `/implexa:record-skill` adds Step 3f.5 (offer to schedule) between the
  preview/activate prompt (3f) and the share prompt (3g). Renders the 4
  cadences via `AskUserQuestion` with the first one marked "(Recommended)";
  user can also type a custom cadence as free-text via the Other input.
- Backend `interview_for_skill` finalize response now includes a
  `recommendedCadences` field on all three branches (new skill, re-record
  into existing, already-finalized idempotent re-call). Heuristic-based
  inference on intent + name + content + tags + tools used:
  - "morning" / "standup" / "yesterday" / "daily brief" → `daily at 8:55am`
  - "hourly" / "pulse" / "scan" / "monitor" → `every 2 hours`
  - "weekly" / "rollup" / "review" → `every monday at 9am`
  - "monthly" / "EOM" / "end of month" → `monthly on the 1st at 9am`
  - catchall → `daily at 9am`
- No new MCP tool; cadence inference rides inside the existing
  `interview_for_skill` finalize response so it adds zero round-trips.

No new permissions or env vars. Existing schedule infra (manifest tables,
`schedule_skill`, `/implexa:run-scheduled` wrapper, `/scheduled` dashboard
page) handles the actual cron registration unchanged.

## [0.8.1] — 2026-05-20

Adds **`slack-plugin` destination type** to the scheduler. Recommended path
for Claude Code users — zero setup if `mcp__plugin_engineering_slack` is
already connected. Backend webhook path (`slack-webhook`) stays as the
cross-vendor fallback for users on other agents.

### Changed
- `/implexa:schedule` slash command now disambiguates Slack intent. If the
  user types a channel name (`#standup`) → `slack-plugin`. If they paste a
  `hooks.slack.com` URL → `slack-webhook`. Bare "slack" → asks.
- `/implexa:run-scheduled` adds Step 2.5: when destination=slack-plugin,
  converts markdown → Slack mrkdwn in-skill and calls
  `mcp__plugin_engineering_slack__send_message` with the channel + body,
  then passes the delivery receipt to `record_scheduled_run` as
  `pluginDelivery`.
- Backend `destination.type` enum: `'slack'` renamed to `'slack-webhook'`,
  `'slack-plugin'` added. Both share the unified `delivery.slack` jsonb
  receipt on `skill_runs` (with `via: webhook|plugin` to disambiguate).
- Dashboard `/scheduled` + `/runs` pages show the destination route
  ("Slack #standup + dashboard" vs "Slack (via webhook) + dashboard").

No migration needed — `destination` is a free-form jsonb column. No live
slack-destinated rows existed when this shipped (v0.8.0 had been live for
~5 min with no Slack users).

## [0.8.0] — 2026-05-20

Adds the **scheduler** surface. `/implexa:schedule` lets users register any
installed skill to run on a recurring cron with output persisted to the
Implexa dashboard and optionally delivered to a Slack channel. This is the
"sticky habit" layer — every morning at 8:55am the brief lands in #standup,
defensibility compounds, and the user can audit history at app.implexa.ai/runs.

The scheduler does NOT run model inference itself. It wraps Claude Code's
`scheduled-tasks` MCP for the cron firing, then adds the manifest, persistence,
and delivery layers that Claude alone does not provide. Zero cost per run.

### Added
- **`/implexa:schedule` slash command** — registers a recurring run. Accepts
  natural-language schedule ("daily at 8:55am", "every weekday at 9am",
  "hourly", "every 30 minutes", plus raw cron). Destinations: dashboard
  (always-on) and Slack incoming webhook (optional). Internally calls the
  new `schedule_skill` MCP tool, then dispatches to
  `mcp__scheduled-tasks__create_scheduled_task` with the prompt
  `/implexa:run-scheduled <id>`.
- **`/implexa:run-scheduled` slash command (internal)** — the callback that
  Claude Code's scheduled-task invokes when a cron fires. Resolves the
  manifest via `get_scheduled_skill_payload`, executes the resolved skill's
  SKILL.md content, then persists output + delivers via
  `record_scheduled_run`. Background-task context: produces no chat output
  beyond a one-line confirmation. Users do NOT invoke this directly.

### Backend (no plugin bump required, but listed for context)
- Migration `0023_scheduled_skills.sql` — `scheduled_skills` (manifest) +
  `skill_runs` (output log) tables with RLS-scoped policies. `skill_runs`
  is generalized: `source ∈ (scheduled, adhoc, orchestration)` so it can
  log non-scheduled runs in the future.
- New MCP tools: `schedule_skill`, `get_scheduled_skill_payload`,
  `record_scheduled_run`. All three thread the user's identity from the
  authenticated MCP session (no caller-supplied userContext).
- New routes: `GET/POST/PATCH/DELETE /api/v2/scheduled-skills` for
  manifest CRUD, `GET /api/v2/scheduled-skills/runs` for the dashboard
  /runs surface.
- NL → cron parser in `src/lib/cron-parser.js`. Covers the 5 most common
  patterns plus raw-cron passthrough.
- Slack incoming-webhook delivery in `src/lib/slack-delivery.js`.
  Converts standard markdown to Slack mrkdwn before posting (`**bold**`
  → `*bold*`, `## H2` → `*H2*`, `[t](u)` → `<u|t>`).

## [0.7.0] — 2026-05-20

Adds the **orchestrator** surface. `/implexa:morning` is the first chain-of-skills
slash command — one command, multiple skills resolved + invoked + logged as a
single orchestration. This is the foundation for the v2 graph recommender
(personalized chain suggestions based on the user's actual run history).

### Added
- **`/implexa:morning` slash command** — chains
  `standup-from-yesterday-commits` + `daily-ai-skills-pulse` into one terse
  morning brief. The skill calls the new `orchestrate_skills` MCP tool, which
  resolves each slug, logs a `skill_invocations` row + awards run karma to
  each creator, and writes a single `orchestrations` row tying the chain
  together. The agent reads each step's SKILL.md body and synthesizes one
  unified output (Yesterday + Today / AI signal / Blockers, capped at 200
  words). Missing-skills case offers `/implexa:fork` install suggestions.
- **`orchestrate_skills` MCP tool** (backend) — generic chain primitive. Input:
  `command` (telemetry label) + `chain` (ordered array of skill slugs, 1-10).
  Returns each step's SKILL.md content for the agent to execute. Terminal
  statuses: `completed` (all resolved), `partial` (some failed), `failed`
  (none resolved). The same primitive will back `/implexa:end-of-day` and
  the eventual `/implexa:do-my-work` open-prompt entry.

### Why
Even at small N (4-5 skills), users (including the founder) start losing
track of which skill maps to which intent. Search-by-name = intent-by-name
breaks once skills overlap in domain. The orchestrator gives users a single
time-anchored entry point that composes the right skills automatically, and
gives Implexa the telemetry substrate (chain frequency, step success rates,
order patterns) to learn personalized recommendations in v2.

## [0.6.1] — 2026-05-19

Config-only patch. Bumps Claude Code's MCP tool timeout for the Implexa
server from the SDK default of 60s to 180s (3 minutes) so finishing a
recording no longer surfaces a cosmetic `MCP error -32001: Request timeout`
while the skill author finalizes.

### Fixed
- **`MCP error -32001: Request timeout` after `/implexa:record-skill`** —
  the finalize path calls Anthropic Haiku to emit 6000-8000 tokens of
  SKILL.md, which routinely takes 30-90s for rich skills. Claude Code's
  bundled MCP SDK caps tool calls at the default `DEFAULT_REQUEST_TIMEOUT_MSEC
  = 60000`, surfacing the timeout error even though the backend completed
  successfully and the skill IS in the user's library. The install script
  now writes `env.MCP_TOOL_TIMEOUT=180000` into `~/.claude/settings.json`
  on every install, so Claude Code waits the full 3 minutes before giving
  up. Existing users on 0.6.0 need to re-run
  `curl -fsSL https://core.implexa.ai/install.sh | bash` to pick up the
  patch (same reinstall pattern as 0.6.0). `.mcp.json`'s `timeout` field
  doesn't work — see [anthropics/claude-code#43791](https://github.com/anthropics/claude-code/issues/43791).

## [0.6.0] — 2026-05-18

Pre-launch polish. The Skill Graph gets a proper update flow, the install
flow gets a universal `curl install.sh | bash` entry point with device-auth,
and a handful of fuzzy-match / discoverability fixes land. This is the last
plugin release before 1.0.0 — install + update paths are stable from here.

### Added
- **`/implexa:update-skill` slash command** — dedicated entry point for
  updating an existing skill by re-recording. Demonstrate the new behavior
  live; the existing SKILL.md gets MERGED with the new demonstration
  (existing steps preserved, new step integrated, error rows appended).
  For text-only changes (typos, renames, copy polish), continue using
  `update_org_skill` (Claude routes there automatically).
- **`/implexa:record-skill` Phase 0 (new vs update branch)** — when
  invoked, asks whether this is a new skill or an update, and routes to
  the right finalize path (`replacingSkillId` set or not). Cross-references
  `/implexa:update-skill` as the preferred entry for the update case.
- **`/implexa:run` + `/implexa:fork` fuzzy-match the public library** —
  when the user's own + org library has no match for their query, the
  run/fork commands expand the search to the public/Trending Globally
  library (via the new `includeUniversal: true` flag on `list_org_skills`).
  If a public skill matches, the user can install + run (or fork
  cross-org without needing a share token).
- **`/implexa:setup` Branch A surfaces authenticated identity** — the
  green "you're connected" confirmation now shows the email + organization
  + plan, so users can verify which account is currently authenticated
  (catches the "wait, am I on my personal or work account?" bug class).
- **Interview options on every question** — the post-demo interview now
  ships 3-4 clickable options per question (rendered via AskUserQuestion)
  instead of free-text. Consistent UX across every captured skill;
  "Other" escape hatch always available for custom answers.

### Changed
- **MERGE MODE for re-record into existing skill** — when
  `/implexa:update-skill` finalizes with `replacingSkillId`, the backend
  now passes the existing SKILL.md to the Haiku author with explicit
  "preserve existing structure, integrate the new demo" instructions.
  Previously hard-replaced (dropped all existing steps not re-demoed).
- **Routine capture from `RemoteTrigger` calls** — skills demonstrated
  with a scheduled-routine setup now bake the cron + prompt spec into
  the SKILL.md as a "Step 0 — set up the daily routine (one-time)"
  section, so forkers inherit the schedule automatically.
- **README rewritten** to mirror the new universal-install positioning
  and the "what's open vs hosted" model (Stripe-CLI / Supabase-style).
- **`update_org_skill` tool description** — explicitly routes behavioral
  changes (new steps, new tool calls, new branches) to
  `/implexa:update-skill` instead of text-editing. Use `update_org_skill`
  for typos, renames, copy polish, restructuring; everything else goes
  through re-record.

### Fixed
- **LICENSE copyright** corrected from Revenoid Inc → Implexa Inc.

### Backend-only changes (no plugin upgrade required to receive these)
- Universal `curl -fsSL https://core.implexa.ai/install.sh | bash` install
  with device-auth (RFC 8628) — works for cold visitors with no token,
  signs them up via browser, auto-installs the plugin + hooks + API key.
- `/api/v2/skills/public` + `/api/v2/skills/stats` endpoints for the
  marketing site's Trending Globally feed.
- Undo Public — revoking a public share now also reverts the skill's
  scope from `universal` back to its previous state (org or private),
  removing it from Trending Globally + the public library.
- Dashboard `/skills/[slug]` page fix — was 404-ing for private skills
  owned by the viewer (used `session.user.id` as an org filter, which
  never matched an org UUID).

### How existing users get this update

Most of you have `autoUpdate: true` set in `~/.claude/plugins/known_marketplaces.json`,
so Claude Code refreshes the marketplace clone on launch. The cache directory
uses the version number, so the new 0.6.0 cache will be populated on next
Claude Code launch. If you don't see the new `/implexa:update-skill` slash
command in autocomplete after a fresh Cmd+Q + relaunch, force-refresh by
re-running the install script:

```bash
curl -fsSL https://core.implexa.ai/install.sh | bash
```

It's idempotent and runs in seconds.

---

## [0.5.0] — 2026-05-15

Adds the explicit "use a skill" entry point. Before this release, skill
reuse depended on Claude routing the user's request ("use my triage
skill") to `apply_org_skill` via natural-language matching. That was
brittle — the model often dropped straight into the underlying tools
(Atlassian, Slack, etc.) instead of recognizing the user wanted to
REUSE a saved skill. Real launch-testing surfaced the gap: "Use my
triage skill" went straight to Atlassian; "Use my Implexa skill for
triage" worked.

The fix: a dedicated `/implexa:run` command that's unambiguous —
fuzzy-matches the user's query against their library and auto-applies
the best match. If no query is given, renders a numbered list and
awaits selection. Powers what's projected to be the most-used surface
(skill reuse compounds over time).

### Added
- `/implexa:run` slash command (skills/run/SKILL.md):
  - Query mode: "use my triage skill" → fuzzy-match in user's library →
    auto-apply (with `createdByMe: true` first, falling back to org-wide)
  - Browse mode: bare `/implexa:run` → numbered list with scope icons
    (🔒 / 👥 / 🌍) → user picks by number or "the X one"
  - Passes any contextual entities (account name, ticket ID, etc.) as
    `invocationArgs` for outcome attribution

### Changed
- `/implexa:my-skills` and `/implexa:org-skills` descriptions now
  explicitly frame themselves as BROWSING lenses and point at
  `/implexa:run` for the REUSE path. Clearer separation of intent.
- Help skill's natural-language phrase table leads with `/implexa:run`
  examples ("Run my triage skill") so Claude prefers it.

## [0.4.0] — 2026-05-14

Adds the personal-library lens. Users were getting `org-skills` overflowing
with team-shared + base Playbooks + public skills and asked for a way to see
just their own captured work. Now there are two clear commands:

- `/implexa:my-skills` (NEW) — only skills the caller authored (private +
  team-shared + public if you made them, but excluding base Playbooks).
  Scope-tagged 🔒/👥/🌍 so the user sees how each is shared at a glance.
- `/implexa:org-skills` — UNCHANGED behavior. The full team-wide view
  (private + org-shared + universal + system Playbooks). Description
  updated to cross-reference `/implexa:my-skills` for the personal lens.

Backend: `list_org_skills` MCP tool gains a `createdByMe: boolean` filter
param (default false). Service-level filter excludes system-scope skills
when `createdByMe: true` — the user didn't author base Playbooks.

### Added
- `/implexa:my-skills` slash command (skills/my-skills/SKILL.md)
- `list_org_skills` MCP tool: new `createdByMe` boolean filter param

### Changed
- `/implexa:org-skills` description now disambiguates: "if user asks for
  MY skills specifically, use /implexa:my-skills instead"

## [0.3.0] — 2026-05-13

Ships the one-command setup automation that bridges plugin-level hooks
(which work in CLI but get sandboxed in Cowork) to user-level hooks
(which fire on every surface).

### Added
- `scripts/install-user-hooks.sh` — bash installer that:
  - Checks for jq, installs via Homebrew if missing
  - Reads `IMPLEXA_API_KEY` from env or prompts the user
  - Writes the launcher at `~/.claude/implexa-hook.sh` (with PATH fix
    + config-file sourcing so GUI-launched Claude can find the API key)
  - Writes config at `~/.claude/implexa.env` (chmod 600)
  - Patches `~/.claude/settings.json` to register hooks for
    UserPromptSubmit, Stop, PostToolUse — idempotent, safe to re-run
  - Backs up the existing settings.json before any change
  - Runs a clean-env smoke test that simulates Claude Desktop's GUI
    environment to catch issues before the user hits them at runtime
- `skills/setup-hooks/SKILL.md` — new `/implexa:setup-hooks` slash
  command. Tells the user to run the installer in their terminal,
  explains what it does, answers common questions (curl-pipe-bash
  security, idempotency, Windows support, etc.).

### Run with
```bash
curl -sL https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/install-user-hooks.sh | bash
```

### Why this exists
The v0.2.x hooks in `hooks/hooks.json` fire in Claude Code CLI but
Claude Desktop / Cowork silently drop plugin-packaged hooks
(documented Cowork sandbox behavior — `--setting-sources user` flag).
v0.3.0 installs the same hook script at the user level via the
documented `~/.claude/settings.json` path, which IS honored on every
surface. The net effect: `conversationTurns > 0` + `toolCallsCount > 0`
in captured demos regardless of where Claude is running.

### Migration
- v0.2.x users: run the installer once. Subsequent plugin updates
  don't need re-running (the launcher resolves the plugin version
  dynamically).
- Fresh users: plugin install → installer → restart Claude. Three
  steps documented on app.implexa.ai/install.

## [0.2.1] — 2026-05-13

Bug fixes to the v0.2.0 host hooks based on a re-read of the official
Claude Code hooks documentation (https://code.claude.com/docs/en/hooks).
The 0.2.0 hooks fired but the captures were degraded due to schema
mismatches with what Claude Code actually sends.

### Fixed
- **PostToolUse hook was reading wrong field names.** Claude Code's
  payload uses `tool_input` and `tool_response` — the 0.2.0 hook was
  reading `tool_args` and `tool_result`. Result: tool calls were
  logged as "Bash tool was used" with empty args + empty response.
  Now correctly reads the documented fields.
- **Event name now read from stdin payload's `hook_event_name` field**
  instead of from `$1`. Per docs, Claude Code does NOT pass the event
  name as a command-line argument — only via the JSON payload. The
  0.2.0 hooks.json passed `UserPromptSubmit` etc. as command args,
  which technically worked via shell tokenization but was fragile.
- **Stop hook now reads `transcript_path` to extract the last assistant
  message.** The 0.2.0 hook guessed at field names (`.response`,
  `.assistant_response`) that aren't in the documented schema. Now
  reads the JSONL transcript file and pulls the last `role=assistant`
  message. Falls back to a marker if transcript isn't accessible.

### Result
Captured skills should now include verbatim user prompts, full Claude
responses, and complete tool arguments + responses. Trace richness
should jump dramatically vs. v0.2.0.

### Migration
No backend changes required. Plugin only — run `claude plugin update`
or wipe `~/.claude/plugins/cache/implexa/` and re-install.

## [0.2.0] — 2026-05-13

Ships the **host-side capture hooks** referenced in 0.1.0 but never installed.
This is the unlock for capturing skills that use non-Implexa tools (computer-use,
Claude_in_Chrome, WebFetch, Bash, Read, Write, native MCP servers) inside a
demonstration. Without these hooks, only Implexa MCP tool calls were
auto-logged and everything else relied on Claude calling `record_demo_note`
manually — brittle and incomplete.

### Added
- `hooks/hooks.json` — registers three hooks via the standard plugin schema:
  - `UserPromptSubmit` → POST `/api/v2/mcp/demo-turn` (role=user)
  - `Stop` → POST `/api/v2/mcp/demo-turn` (role=assistant)
  - `PostToolUse` → POST `/api/v2/mcp/demo-tool-call`
- `hooks/implexa-event.sh` — bash dispatcher. Reads stdin JSON, picks the
  right endpoint, POSTs with `IMPLEXA_API_KEY`. Fire-and-forget (3s timeout,
  silent on failure) so a slow/offline backend never blocks Claude.

### Privacy
- Hooks ONLY forward data when an active demo session exists in the user's
  Implexa org. Backend silently drops events when no recording is in
  progress — installing the plugin ≠ always-on surveillance.

### Requires
- `core.implexa.ai` running v0.1.x with `POST /api/v2/mcp/demo-tool-call`
  endpoint (companion commit in implexa-backend).
- User has `IMPLEXA_API_KEY` set in their shell env.

## [0.1.0] — 2026-05-12

Initial release. Forked from Revenoid's Skill Graph layer (revenoid-claude-plugin@v0.1.3) and rebranded as a standalone product focused exclusively on workflow capture + sharing.

### Added
- 11 plugin skills:
  - `/implexa:record-skill` — three-phase demonstration recording (start → optional free-text → interview → finalize → offer to share)
  - `/implexa:save-this` — post-hoc workflow capture
  - `/implexa:org-skills` — browse + invoke saved org skills
  - `/implexa:playbooks` — browse the horizontal Playbook library
  - `/implexa:fork` — clone a Playbook or peer skill
  - `/implexa:share-this` — generate share link (team-gated or public)
  - `/implexa:skill-roi` — outcome attribution rollup
  - `/implexa:get-me-started` — first-run activation
  - `/implexa:credits` — credit balance check
  - `/implexa:setup` — connect integrations
  - `/implexa:help` — onboarding
- ~26 MCP tools via `@implexa/mcp-server` proxy → `core.implexa.ai`
  - 11 Skill Graph tools (start/end_demo, interview, list/apply/fork_org_skill, capture, attribute_outcome, create_share_link, record_demo_note, record_demo_freetext)
  - 14 external-data tools (Fiber AI + Coresignal + Apollo)
  - 1 `draft_message` (Anthropic SDK direct)
- Domain-gated share links + public share links
- Host-side conversation forwarding via UserPromptSubmit + Stop + PostToolUse hooks
- Three capture surfaces during recording (tool calls / record_demo_note / full transcript)
- Skill author with 6-component structured output via Anthropic Haiku
- Post-demo interview (Haiku-generated, 2–4 targeted questions)

### Removed (vs. Revenoid fork point)
- All sales/recruiting vertical plugin skills (account-plan, pre-call-prep, prospect-account, find-and-engage, enrich-and-sync, bullhorn-standup, fill-this-role, redeploy-candidate, messaging-policy, icp, agents)
- Revenoid-internal MCP tools (research_account, messaging-agent generate_message, get_lead_list*, revenoid_workflow, etc.)
- All Revenoid branding throughout
