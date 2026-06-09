---
description: 'Schedule any installed agent to run on a recurring schedule (daily, weekly, hourly) with output delivered to the Implexa dashboard or to a Slack channel via incoming webhook. Use when the user says "schedule this skill", "schedule this agent", "run X daily", "every morning run Y", "set up a daily standup", "auto-run my morning brief", "run hackernews-and-x-comment-drafter every day at 9am", or invokes /implexa:schedule. THE Implexa-native scheduling primitive - replaces ad-hoc "schedule this for me" requests with a real registered manifest, persistent output log, and optional Slack delivery. Wraps Claude Code''s scheduled-tasks MCP with the manifest + destination layer Claude alone doesn''t provide.'
---

# Schedule an agent to run recurringly

Register a recurring run for any agent in the user's library. The output gets persisted to the Implexa dashboard (always-on) and optionally posted to a Slack channel via incoming webhook.

This agent scheduler **wraps** Claude Code's `scheduled-tasks` MCP. Implexa stores the manifest (what's scheduled, when, where it goes); Claude Code's runtime owns the cron firing; when the task fires, it invokes the wrapper `/implexa:run-scheduled` which executes the real agent and persists the output.

---

## Step 1 - Parse the user's request into structured args

Extract three things from the user's free-form input:

- **`skillSlug`** (required): the slug of the agent to schedule. Examples: `standup-from-yesterday-commits`, `daily-ai-skills-pulse`, `hackernews-and-x-comment-drafter`. If the user used a fuzzy name ("run my morning brief"), resolve it by calling `list_org_skills` and picking the best match.

- **`scheduleNl`** (required): the natural-language schedule. Pass it through verbatim from the user. Supported patterns:
  - `"daily at 8:55am"` / `"every day at 17:30"`
  - `"every weekday at 9am"`
  - `"every monday at 9am"` (any weekday name)
  - `"every hour"` / `"hourly"`
  - `"every 30 minutes"` (1-59)
  - `"every 2 hours"` (1-23) ← new in v0.8.3
  - `"every 3 days"` (1-30, runs at midnight in the schedule's timezone) ← new in v0.8.3
  - raw cron: `"55 8 * * *"` (reverse-humanized to natural prose when displayed back)

- **`destination`** (optional, default `{type:"dashboard"}`):

  Three options. Pick based on what the user said:

  **(a) `{ type: "dashboard" }`** - default. Output lands at app.implexa.ai/runs.

  **(b) `{ type: "slack-plugin", target: "<channel>" }`** - RECOMMENDED when the user wants Slack delivery AND `mcp__plugin_engineering_slack__send_message` is available (i.e. the user has the Claude Code Slack plugin connected; check via `mcp__plugin_engineering_slack__authenticate` if unsure). Zero setup; Claude posts to the channel directly in-session when the schedule fires.

  Target is the channel: `"#standup"`, `"#general"`, a channel ID like `"C0123456789"`, or a DM ID like `"D012345678"`.

  **(c) `{ type: "slack-webhook", target: "<webhook-url>" }`** - fallback when the user has a Slack incoming-webhook URL ready (e.g. they pasted one, or they're using a different agent that doesn't have a Slack plugin). The Implexa backend POSTs to the URL server-side; works without Claude in the loop.

  ## How to choose between slack-plugin and slack-webhook

  1. If the user pastes a `https://hooks.slack.com/...` URL → **slack-webhook**.
  2. If the user gives a channel name (with or without #) → **slack-plugin**. Confirm by calling `mcp__plugin_engineering_slack__authenticate` first to ensure the plugin is connected. If not connected, prompt the user to connect via `/mcp` first, OR offer to fall back to slack-webhook with a URL.
  3. If the user just says "slack" without specifying → ask: "Channel name (#standup, uses your Slack plugin) or webhook URL (works without the plugin)?"

  ## Default destination

  If the user gave only the agent slug + schedule without mentioning Slack, **do not ask** for Slack details. Default to dashboard. They can add Slack later by re-running /implexa:schedule with the same args + a destination.

- **`postRunAction`** (optional): a side-effecting step the run-scheduled wrapper runs AFTER the agent produces its deliverable, stored on the schedule so the routine prompt stays a thin `/run-scheduled <id>` shim. **Capture this when the user wants the run's output PUBLISHED or applied to a repo**, e.g. "schedule the seo agent weekly and publish drafts to my implexa-website repo". v1 shape:

  ```jsonc
  {
    "type": "publish-content",
    "repo": "<absolute path to the repo on this machine, e.g. /Users/you/.../implexa-website>",
    "script": "scripts/publish-draft-post.mjs",   // optional, this is the default
    "artifact_path": "/tmp/implexa-seo.md"          // optional, this is the default
  }
  ```

  Resolve `repo` to the absolute path of the user's repo (infer from the workspace, or ask once if ambiguous). **Omit `postRunAction` entirely** if the user did not ask to publish/apply output anywhere. Capture it ONCE here; improving the agent later never requires changing the routine prompt.

## Step 1.5: Resolve agent config BEFORE scheduling (workflow-backed agents only)

If you're scheduling a workflow-backed **agent** (you'll pass `source` to `schedule_skill`), its first run is **unattended**: no one is there to answer setup questions when the schedule fires at 9am tomorrow. So resolve the config NOW, at schedule time, so day-1 runs hands-free. This is the difference between a schedule that just works and one that stalls its first run on a question no one can answer.

1. Call **`get_workflow_setup`** with the agent's `slug` + `source` (or `workflow_id`).
2. If `complete` is true, the user already answered; reuse verbatim, skip to Step 2.
3. If not complete, ask the returned `questions` ONE at a time via **`AskUserQuestion`** (offer the `options` for `kind:"choice"`; let them type their own). Then call **`save_workflow_setup`** with `{ slug, source, config }` (the flat answer map).
4. Only proceed once setup is `complete`, unless the user explicitly says "schedule it anyway", in which case warn that the first run may stall on the missing config.

Skip this step entirely for plain library agent schedules (no `source`); those agents don't carry a config interview.

## Step 1.6: Watch / until triggers (loop-powered, workflow-backed agents only)

If the user wants the agent to fire **reactively** ("**when** my competitor changes pricing, run it", "run it **when** CI goes green") or to **converge** ("keep running **until** the draft passes the critique", "**until** I have 10 leads") rather than on a clock, this is a `/loop`-powered routine, not cron. It applies to a workflow-backed **agent** (pass `source`), not a plain library agent.

1. Call **`schedule_skill`** with: `skillSlug` (the agent slug), `source`, `trigger: "watch"` (event-driven) or `"until"` (converging), `watchCondition` (the event for watch, or the success condition for until, in one line), `destination` (e.g. `{ "type": "email" }`). NO `scheduleNl` - there's no clock.
2. The tool returns a **`loopInvocation`** string. Give it to the user to paste verbatim:

   ```
   ▶ Start it live, paste this in your agent:
     <loopInvocation>
   ```

   It runs inside a Claude `/loop` session: `watch` arms a Monitor and runs the agent when the event fires; `until` re-runs to convergence (bounded by a max-iterations guard). Each iteration logs to app.implexa.ai/runs.
3. **Skip Steps 2 and 3** (no cron, no `create_scheduled_task`). Be honest: it runs **while the session is open**; for a durable always-on cadence, use a cron schedule instead.

For an ordinary clock schedule, continue to Step 2.

## Step 2 - Call `schedule_skill`

Call `schedule_skill` with the parsed args:

```jsonc
{
  "skillSlug":   "daily-ai-skills-pulse",  // the agent's slug
  "scheduleNl": "daily at 8:55am",
  "destination": { "type": "dashboard" }
  // OR { "type": "slack-plugin",  "target": "#standup" }
  // OR { "type": "slack-webhook", "target": "https://hooks.slack.com/services/T.../B.../XXX" }
  // optional, ONLY when the user wants output published to a repo:
  // "postRunAction": { "type": "publish-content", "repo": "/Users/you/.../implexa-website" }
}
```

The tool returns:

```jsonc
{
  "ok": true,
  "scheduledSkillId": "uuid",
  "skillSlug":         "daily-ai-skills-pulse",
  "cronExpression":    "55 8 * * *",
  "humanizedSchedule": "8:55 AM every day",
  "timezone":          "UTC",
  "destination":       { "type": "dashboard" },
  "claudeScheduledTaskPrompt": "/implexa:run-scheduled <uuid>",
  "nextAction":        "Now call create_scheduled_task with: prompt=..., cron=..., tz=..."
}
```

If `ok === false`, the tool returns an `error` string. Common cases:
- Unknown agent slug - ask the user to install/fork it first
- Unparseable schedule - echo the supported patterns from the error message
- Invalid Slack webhook URL - ask user to paste a real `hooks.slack.com` URL

The return also carries **`permissionManifest`** - the exact tools + fetch domains this agent needs. Step 2.7 pre-grants it.

## Step 2.7 - Pre-grant the permission manifest (so the unattended run never stalls)

This is the reliability step that prevents the silent-stall failure: an agent runs in the user's own Claude Code (presence not runtime), so a scheduled run inherits Claude Code's permission prompts. With nobody there to click "Allow Claude to fetch implexa.ai?", an un-approved tool is a dead stop with NO error, and silence reads as success. (This is the exact trap a scheduled SEO agent hit on 2026-06-08, waited an hour.) Pre-grant the manifest ONCE here so the unattended run executes under a pre-approved allowlist and never hits a prompt.

`schedule_skill`'s return carries `permissionManifest`:

```jsonc
{
  "version": 1,
  "summary": "fetches implexa.ai and runs web research",   // plain-language, for the consent line
  "rules":   ["mcp__implexa__*","WebSearch","WebFetch(domain:implexa.ai)", ...],  // scoped Claude Code allow rules
  "domains": ["implexa.ai"],
  "requires_browser": false
}
```

1. **Ask once.** Use `AskUserQuestion`:
   > This agent **<permissionManifest.summary>**. Allow it for unattended runs? The grant is scoped to exactly these tools, never blanket access, and you can revoke it in `~/.claude/settings.json`.


   Options: **Allow for unattended runs** / **Not now**.

2. **On "Not now":** skip the pre-grant. Warn in one line that the first scheduled run may stall on a permission prompt until they allow it, then continue to Step 3 anyway. Do NOT block the schedule on this.

3. **On allow:** write the manifest object to a temp file and run the bundled pre-grant script via **Bash** (structured args, never an arbitrary string):
   - Write the whole `permissionManifest` object to `/tmp/implexa-permission-manifest.json`.
   - Run: `node "${CLAUDE_PLUGIN_ROOT}/scripts/apply-permission-manifest.mjs" --file /tmp/implexa-permission-manifest.json`

   The script (additive + idempotent, never a blanket bypass):
   - merges the scoped `rules` into `~/.claude/settings.json` `permissions.allow` (Claude Code applies these to scheduled-task sessions, so the pre-approved tools run without a prompt);
   - writes a scheduled-run-scoped `~/.claude/scheduled-tasks/.claude/settings.json` with `permissions.defaultMode: "dontAsk"` + the same rules, so an UNFORESEEN tool (one not in the manifest) is denied-and-continue, failing FAST and VISIBLY (a clear failed run you can one-tap fix) instead of hanging. Interactive sessions are unaffected.

4. **Read the script's JSON output.** On `ok:true`, tell the user in one line: `Pre-approved for unattended runs: <permissionManifest.summary>`. If the script errors (e.g. it refuses a malformed rule, or settings.json is unreadable), surface the error but continue, the schedule is still valid (the run may just prompt).

5. **If `permissionManifest.requires_browser` is true:** note that this agent drives the browser, so it must run while the machine is on (it cannot move to a remote routine). The pre-grant still applies for its local runs.

## Step 2.8 - Reachability gate (do not schedule an agent against an inbox it cannot reach)

Pre-granting permissions makes the unattended run *run*; it does not make the accounts it needs *reachable*. A browser-driving agent signs into the user's real accounts (Gmail, a CRM, a calendar) through the paired Chrome profile. If a needed account is not signed in to any paired profile, the scheduled run will hit it, degrade, and produce a partial result, silently, every fire. Catch that here, at schedule time, while the user is present to fix it.

This is a **recommendation, not a hard block.** You always let the user proceed. But an unreachable account must be SURFACED, never swallowed.

**When to run this gate:** when `permissionManifest.requires_browser` is true (the clear signal the agent drives signed-in accounts). For a pure API / web-research agent (`requires_browser` false) there is no inbox to reach, skip straight to Step 3.

1. **Read the connections status.** Call `get_connection_status` with `{ scheduledSkillId }` (from Step 2). This is the backend Connections read: it derives the agent's REQUIRED accounts/domains from its stored permission manifest and returns them against what the desktop has verified as reachable. Documented shape:

   ```jsonc
   {
     "ok": true,
     "scheduledSkillId": "uuid",
     "requires_browser": true,
     "needed":      [ { "kind": "domain",  "identifier": "mail.google.com", "account_hint": "founder@implexa.ai" } ],
     "reachable":   [ { "identifier": "mail.google.com", "profile": "dedicated", "verified_at": "2026-06-08T..." } ],
     "unreachable": [ { "kind": "account", "identifier": "rabi@implexa.ai", "reason": "not signed in to any paired profile" } ],
     "unknown":     [ { "kind": "domain",  "identifier": "app.hubspot.com", "reason": "never verified" } ],
     "warnings":    [ "Gmail account rabi@implexa.ai is not reachable in any paired Chrome profile." ]
   }
   ```

2. **Best-effort, never block on the read itself.** If `get_connection_status` is not available in this session (the backend Connections stream may not be live yet), or returns `ok:false` or errors, skip the gate silently and continue to Step 3. A missing reachability read must never stop a schedule.

3. **If `needed` is empty, or `unreachable` and `unknown` are both empty:** everything the agent needs is reachable. Say nothing extra, continue to Step 3.

4. **If any needed account/domain is `unreachable` (or `unknown`):** WARN prominently and offer to connect now via `AskUserQuestion`:

   > `<skillSlug>` needs **<list the unreachable identifiers + account hints>**, which <isn't / aren't> reachable in your paired Chrome profile yet. Scheduled runs will degrade until you connect <it / them>. Connect now, or schedule anyway?

   Options: **Connect now (recommended)** / **Schedule anyway**.

   - **Connect now:** the plugin cannot pair Chrome itself (the desktop owns pairing). Steer the user to the Implexa desktop app's "set up your agents' workspace" step, or app.implexa.ai/connections, and tell them to sign each listed account into the **dedicated** profile (the reliable home; main is best-effort backup only). After they say they have done it, re-call `get_connection_status` to VERIFY (do not assume) before finalizing. Repeat until the needed accounts are reachable, or the user chooses to proceed anyway.
   - **Schedule anyway:** continue to Step 3. Carry the unreachable list into Step 4 so the confirmation surfaces it; do not let it vanish.

5. `unknown` (never-verified) accounts are a softer signal than `unreachable`: mention them as "not yet verified, connect to be safe" but do not push as hard as a confirmed-unreachable account.

## Step 3 - Register with Claude Code's scheduled-tasks MCP

Call **`mcp__scheduled-tasks__create_scheduled_task`** with:

- `prompt`: the `claudeScheduledTaskPrompt` from Step 2's return (e.g. `/implexa:run-scheduled <uuid>`)
- `cron`: the `cronExpression` from Step 2 (e.g. `"55 8 * * *"`)
- `timezone`: the `timezone` from Step 2 (e.g. `"UTC"` or the user's IANA tz)

If `create_scheduled_task` returns a task ID, optionally call back into Implexa to attach it (future: `attach_claude_task_id` MCP tool, not required for v1).

If `create_scheduled_task` fails (e.g. MCP not available, permission denied), surface the error clearly and tell the user they can manually paste this prompt into a scheduling tool of their choice. Don't delete the Implexa manifest; they can manually trigger runs via `/implexa:run-scheduled <id>` until they re-register the cron.

## Step 4 - Confirm to the user

Render a concise confirmation:

```
✓ Scheduled `<skillSlug>` <humanizedSchedule>.
  Output → <destination summary>
  Manage at: app.implexa.ai/scheduled
```

Where `<destination summary>` is:
- `Implexa dashboard only` (default)
- `Slack <channel> + Implexa dashboard` (when `slack-plugin` configured; echo the channel name back)
- `Slack (via webhook) + Implexa dashboard` (when `slack-webhook` configured; do NOT echo the webhook URL)

Keep it ≤ 4 lines. Do not echo the cron expression unless the user asked for it.

**If Step 2.8 left any account unreachable** (the user chose "Schedule anyway"), append one honest line so the gap is visible at a glance:

```
⚠ Needs connecting: <unreachable accounts/domains>. Runs degrade until reachable. Connect at app.implexa.ai/connections.
```

## What's next?

Schedule management is now available from inside Claude Code (no dashboard hop needed):

- `Pause this schedule` → `mcp__implexa__pause_scheduled_skill({ scheduledSkillId })` - flip status to paused. The cron task at Claude's runtime still fires but the wrapper short-circuits until resume. Idempotent.
- `Resume a paused schedule` → `mcp__implexa__resume_scheduled_skill({ scheduledSkillId })` - flip back to active. Also accepts failed rows for best-effort recovery.
- `Delete a schedule` → `mcp__implexa__delete_scheduled_skill({ scheduledSkillId })` - hard-delete the manifest. Historical runs at app.implexa.ai/runs are preserved. Note: Claude Code's scheduled-task is still registered and may fire once before going dormant; to fully clean up, also remove the task from Claude Code's scheduled-tasks sidebar.
- `List all my schedules` → `mcp__implexa__list_scheduled_skills({})` - returns every schedule with natural-prose humanizedSchedule, nextRunInfo, destinationLabel, runCount, lastRunAt.
- `Run it once now to test` - invoke `/implexa:run-scheduled <id>` directly.
- `Manage in the dashboard` - app.implexa.ai/scheduled is still live as the visual alternative.

## Notes for the model

- **Default to dashboard destination** unless the user explicitly mentions Slack. Asking for a Slack webhook URL when they didn't ask for Slack is friction. They can add it later from /scheduled.
- **Slack webhook URLs are not secret-secret but should not be echoed back to the user.** When confirming, say "Slack channel" not "https://hooks.slack.com/services/T.../B.../XXX".
- **Reuse the user's typed schedule string** when calling `schedule_skill`. The natural-language parser handles capitalization and whitespace, but it expects the rough English shape the user typed.
- **One slash command, one schedule.** Don't try to register two schedules in one invocation. If the user wants two, run /implexa:schedule twice.
- **Telemetry is automatic.** The schedule_skill tool writes the manifest + the wrapper agent writes each run to skill_runs. Nothing else to log here.

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `schedule_skill` returns ok=false with "Skill not found" | The agent isn't in the user's library | "I couldn't find `<slug>` in your library. Fork it from a Playbook or install via a share link, then re-run /implexa:schedule." |
| `schedule_skill` returns ok=false with "Could not parse schedule" | NL parser couldn't match a pattern | Echo the supported patterns from the error message. Ask the user to rephrase. |
| `schedule_skill` returns ok=false with "slack-webhook destination requires..." | Webhook URL invalid or missing | Ask the user to paste a real `hooks.slack.com/services/...` URL, OR switch to slack-plugin if they meant a channel name. |
| `schedule_skill` returns ok=false with "slack-plugin destination requires..." | Channel target missing or too short | Ask the user for the channel name (e.g. `#standup`) or paste a channel ID. |
| User wants slack-plugin but `mcp__plugin_engineering_slack__authenticate` fails | Slack plugin not connected to Claude Code | Tell the user: "Your Slack plugin isn't connected. Run `/mcp` in Claude Code and authenticate the Slack plugin, OR fall back to a `slack-webhook` destination with a `hooks.slack.com` URL." |
| `mcp__scheduled-tasks__create_scheduled_task` is not available | Claude Code version doesn't expose scheduled-tasks MCP | Tell the user: "The Implexa manifest is saved (id=<id>), but Claude Code's scheduled-tasks MCP isn't available in this session. Run /implexa:run-scheduled <id> manually for now, or upgrade Claude Code and re-register." |
| `create_scheduled_task` errors with permission denied | User hasn't granted Claude scheduled-tasks permission | Tell the user: "Claude Code needs permission to create scheduled tasks. Grant it via /mcp, then re-run /implexa:schedule." |
| Schedule registered but later runs never fire | Cron task lost in Claude Code restart, or user revoked scheduled-tasks permission | Tell the user to check /mcp for the scheduled-tasks server status, then re-run /implexa:schedule to re-register. |
| `get_connection_status` is not available / returns ok=false (Step 2.8) | Backend Connections read not live in this session | Skip the reachability gate silently and schedule normally. Never block a schedule on a missing reachability read. |
