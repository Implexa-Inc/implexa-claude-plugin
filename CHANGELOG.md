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
