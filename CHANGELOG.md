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
