---
description: 'Schedule any installed skill to run on a recurring schedule (daily, weekly, hourly) with output delivered to the Implexa dashboard or to a Slack channel via incoming webhook. Use when the user says "schedule this skill", "run X daily", "every morning run Y", "set up a daily standup", "auto-run my morning brief", "run hackernews-and-x-comment-drafter every day at 9am", or invokes /implexa:schedule. THE Implexa-native scheduling primitive — replaces ad-hoc "schedule this for me" requests with a real registered manifest, persistent output log, and optional Slack delivery. Wraps Claude Code''s scheduled-tasks MCP with the manifest + destination layer Claude alone doesn''t provide.'
---

# Schedule a skill to run recurringly

Register a recurring run for any skill in the user's library. The output gets persisted to the Implexa dashboard (always-on) and optionally posted to a Slack channel via incoming webhook.

This skill **wraps** Claude Code's `scheduled-tasks` MCP. Implexa stores the manifest (what's scheduled, when, where it goes); Claude Code's runtime owns the cron firing; when the task fires, it invokes the wrapper skill `/implexa:run-scheduled` which executes the real skill and persists the output.

---

## Step 1 — Parse the user's request into structured args

Extract three things from the user's free-form input:

- **`skillSlug`** (required): the slug of the skill to schedule. Examples: `standup-from-yesterday-commits`, `daily-ai-skills-pulse`, `hackernews-and-x-comment-drafter`. If the user used a fuzzy name ("run my morning brief"), resolve it by calling `list_org_skills` and picking the best match.

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

  **(a) `{ type: "dashboard" }`** — default. Output lands at app.implexa.ai/runs.

  **(b) `{ type: "slack-plugin", target: "<channel>" }`** — RECOMMENDED when the user wants Slack delivery AND `mcp__plugin_engineering_slack__send_message` is available (i.e. the user has the Claude Code Slack plugin connected — check via `mcp__plugin_engineering_slack__authenticate` if unsure). Zero setup; Claude posts to the channel directly in-session when the schedule fires.

  Target is the channel: `"#standup"`, `"#general"`, a channel ID like `"C0123456789"`, or a DM ID like `"D012345678"`.

  **(c) `{ type: "slack-webhook", target: "<webhook-url>" }`** — fallback when the user has a Slack incoming-webhook URL ready (e.g. they pasted one, or they're using a different agent that doesn't have a Slack plugin). The Implexa backend POSTs to the URL server-side; works without Claude in the loop.

  ## How to choose between slack-plugin and slack-webhook

  1. If the user pastes a `https://hooks.slack.com/...` URL → **slack-webhook**.
  2. If the user gives a channel name (with or without #) → **slack-plugin**. Confirm by calling `mcp__plugin_engineering_slack__authenticate` first to ensure the plugin is connected. If not connected, prompt the user to connect via `/mcp` first, OR offer to fall back to slack-webhook with a URL.
  3. If the user just says "slack" without specifying → ask: "Channel name (#standup, uses your Slack plugin) or webhook URL (works without the plugin)?"

  ## Default destination

  If the user gave only the skill slug + schedule without mentioning Slack, **do not ask** for Slack details. Default to dashboard. They can add Slack later by re-running /implexa:schedule with the same args + a destination.

- **`postRunAction`** (optional): a side-effecting step the run-scheduled wrapper runs AFTER the workflow produces its deliverable, stored on the schedule so the routine prompt stays a thin `/run-scheduled <id>` shim. **Capture this when the user wants the run's output PUBLISHED or applied to a repo**, e.g. "schedule the seo workflow weekly and publish drafts to my implexa-website repo". v1 shape:

  ```jsonc
  {
    "type": "publish-content",
    "repo": "<absolute path to the repo on this machine, e.g. /Users/you/.../implexa-website>",
    "script": "scripts/publish-draft-post.mjs",   // optional, this is the default
    "artifact_path": "/tmp/implexa-seo.md"          // optional, this is the default
  }
  ```

  Resolve `repo` to the absolute path of the user's repo (infer from the workspace, or ask once if ambiguous). **Omit `postRunAction` entirely** if the user did not ask to publish/apply output anywhere. Capture it ONCE here; improving the workflow later never requires changing the routine prompt.

## Step 2 — Call `schedule_skill`

Call `schedule_skill` with the parsed args:

```jsonc
{
  "skillSlug":   "daily-ai-skills-pulse",
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
- Unknown skill slug → ask the user to install/fork it first
- Unparseable schedule → echo the supported patterns from the error message
- Invalid Slack webhook URL → ask user to paste a real `hooks.slack.com` URL

## Step 3 — Register with Claude Code's scheduled-tasks MCP

Call **`mcp__scheduled-tasks__create_scheduled_task`** with:

- `prompt`: the `claudeScheduledTaskPrompt` from Step 2's return (e.g. `/implexa:run-scheduled <uuid>`)
- `cron`: the `cronExpression` from Step 2 (e.g. `"55 8 * * *"`)
- `timezone`: the `timezone` from Step 2 (e.g. `"UTC"` or the user's IANA tz)

If `create_scheduled_task` returns a task ID, optionally call back into Implexa to attach it (future: `attach_claude_task_id` MCP tool — not required for v1).

If `create_scheduled_task` fails (e.g. MCP not available, permission denied), surface the error clearly and tell the user they can manually paste this prompt into a scheduling tool of their choice. Don't delete the Implexa manifest — they can manually trigger runs via `/implexa:run-scheduled <id>` until they re-register the cron.

## Step 4 — Confirm to the user

Render a concise confirmation:

```
✓ Scheduled `<skillSlug>` <humanizedSchedule>.
  Output → <destination summary>
  Manage at: app.implexa.ai/scheduled
```

Where `<destination summary>` is:
- `Implexa dashboard only` (default)
- `Slack <channel> + Implexa dashboard` (when `slack-plugin` configured — echo the channel name back)
- `Slack (via webhook) + Implexa dashboard` (when `slack-webhook` configured — do NOT echo the webhook URL)

Keep it ≤ 4 lines. Do not echo the cron expression unless the user asked for it.

## What's next?

Schedule management is now available from inside Claude Code (no dashboard hop needed):

- `Pause this schedule` → `mcp__implexa__pause_scheduled_skill({ scheduledSkillId })` — flip status to paused. The cron task at Claude's runtime still fires but the wrapper short-circuits until resume. Idempotent.
- `Resume a paused schedule` → `mcp__implexa__resume_scheduled_skill({ scheduledSkillId })` — flip back to active. Also accepts failed rows for best-effort recovery.
- `Delete a schedule` → `mcp__implexa__delete_scheduled_skill({ scheduledSkillId })` — hard-delete the manifest. Historical runs at app.implexa.ai/runs are preserved. Note: Claude Code's scheduled-task is still registered and may fire once before going dormant; to fully clean up, also remove the task from Claude Code's scheduled-tasks sidebar.
- `List all my schedules` → `mcp__implexa__list_scheduled_skills({})` — returns every schedule with natural-prose humanizedSchedule, nextRunInfo, destinationLabel, runCount, lastRunAt.
- `Run it once now to test` — invoke `/implexa:run-scheduled <id>` directly.
- `Manage in the dashboard` — app.implexa.ai/scheduled is still live as the visual alternative.

## Notes for the model

- **Default to dashboard destination** unless the user explicitly mentions Slack. Asking for a Slack webhook URL when they didn't ask for Slack is friction. They can add it later from /scheduled.
- **Slack webhook URLs are not secret-secret but should not be echoed back to the user.** When confirming, say "Slack channel" not "https://hooks.slack.com/services/T.../B.../XXX".
- **Reuse the user's typed schedule string** when calling `schedule_skill`. The natural-language parser handles capitalization and whitespace, but it expects the rough English shape the user typed.
- **One slash command, one schedule.** Don't try to register two schedules in one invocation. If the user wants two, run /implexa:schedule twice.
- **Telemetry is automatic.** The schedule_skill tool writes the manifest + the wrapper skill writes each run to skill_runs. Nothing else for this skill to log.

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `schedule_skill` returns ok=false with "Skill not found" | The skill isn't in the user's library | "I couldn't find `<slug>` in your library. Fork it from a Playbook or install via a share link, then re-run /implexa:schedule." |
| `schedule_skill` returns ok=false with "Could not parse schedule" | NL parser couldn't match a pattern | Echo the supported patterns from the error message. Ask the user to rephrase. |
| `schedule_skill` returns ok=false with "slack-webhook destination requires..." | Webhook URL invalid or missing | Ask the user to paste a real `hooks.slack.com/services/...` URL, OR switch to slack-plugin if they meant a channel name. |
| `schedule_skill` returns ok=false with "slack-plugin destination requires..." | Channel target missing or too short | Ask the user for the channel name (e.g. `#standup`) or paste a channel ID. |
| User wants slack-plugin but `mcp__plugin_engineering_slack__authenticate` fails | Slack plugin not connected to Claude Code | Tell the user: "Your Slack plugin isn't connected. Run `/mcp` in Claude Code and authenticate the Slack plugin, OR fall back to a `slack-webhook` destination with a `hooks.slack.com` URL." |
| `mcp__scheduled-tasks__create_scheduled_task` is not available | Claude Code version doesn't expose scheduled-tasks MCP | Tell the user: "The Implexa manifest is saved (id=<id>), but Claude Code's scheduled-tasks MCP isn't available in this session. Run /implexa:run-scheduled <id> manually for now, or upgrade Claude Code and re-register." |
| `create_scheduled_task` errors with permission denied | User hasn't granted Claude scheduled-tasks permission | Tell the user: "Claude Code needs permission to create scheduled tasks. Grant it via /mcp, then re-run /implexa:schedule." |
| Schedule registered but later runs never fire | Cron task lost in Claude Code restart, or user revoked scheduled-tasks permission | Tell the user to check /mcp for the scheduled-tasks server status, then re-run /implexa:schedule to re-register. |
