---
description: Schedule any installed skill to run on a recurring schedule (daily, weekly, hourly) with output delivered to the Implexa dashboard or to a Slack channel via incoming webhook. Use when the user says "schedule this skill", "run X daily", "every morning run Y", "set up a daily standup", "auto-run my morning brief", "run hackernews-and-x-comment-drafter every day at 9am", or invokes /implexa:schedule. THE Implexa-native scheduling primitive — replaces ad-hoc "schedule this for me" requests with a real registered manifest, persistent output log, and optional Slack delivery. Wraps Claude Code's scheduled-tasks MCP with the manifest + destination layer Claude alone doesn't provide.
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
  - raw cron: `"55 8 * * *"`

- **`destination`** (optional, default `{type:"dashboard"}`):
  - If the user mentioned Slack ("post to slack", "send to #standup", "slack webhook"), ask for the webhook URL if they didn't paste one. Set `destination = { type: "slack", target: "<webhook-url>" }`.
  - Otherwise default to `{ type: "dashboard" }` — output lands at app.implexa.ai/runs.

If the user gave only the skill slug + schedule without a destination, **do not ask** for Slack details. Default to dashboard. They can add Slack later by editing the schedule.

## Step 2 — Call `schedule_skill`

Call `schedule_skill` with the parsed args:

```jsonc
{
  "skillSlug":   "daily-ai-skills-pulse",
  "scheduleNl": "daily at 8:55am",
  "destination": { "type": "dashboard" }
  // OR { "type": "slack", "target": "https://hooks.slack.com/services/T.../B.../XXX" }
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
- `Slack channel <inferred from webhook> + Implexa dashboard` (when Slack configured)

Keep it ≤ 4 lines. Do not echo the cron expression unless the user asked for it.

## What's next?

- `Pause this schedule` — call `mcp__implexa__schedule_skill` with `status:paused` patch (v2; for now, dashboard /scheduled has the toggle)
- `Run it once now to test` — invoke `/implexa:run-scheduled <id>` directly
- `Show me my scheduled skills` — load app.implexa.ai/scheduled or list via the API

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
| `schedule_skill` returns ok=false with "Slack destination requires..." | Webhook URL invalid or missing | Ask the user to paste a real `hooks.slack.com/services/...` URL or drop the Slack destination. |
| `mcp__scheduled-tasks__create_scheduled_task` is not available | Claude Code version doesn't expose scheduled-tasks MCP | Tell the user: "The Implexa manifest is saved (id=<id>), but Claude Code's scheduled-tasks MCP isn't available in this session. Run /implexa:run-scheduled <id> manually for now, or upgrade Claude Code and re-register." |
| `create_scheduled_task` errors with permission denied | User hasn't granted Claude scheduled-tasks permission | Tell the user: "Claude Code needs permission to create scheduled tasks. Grant it via /mcp, then re-run /implexa:schedule." |
| Schedule registered but later runs never fire | Cron task lost in Claude Code restart, or user revoked scheduled-tasks permission | Tell the user to check /mcp for the scheduled-tasks server status, then re-run /implexa:schedule to re-register. |
