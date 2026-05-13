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
