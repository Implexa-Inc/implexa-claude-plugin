---
description: 'Internal callback skill invoked by Claude Code''s scheduled-tasks runtime when a recurring Implexa schedule fires. Use ONLY when Claude is dispatched via a scheduled task with a prompt like "/implexa:run-scheduled <uuid>" — humans should not invoke this directly. THE Implexa scheduler execution path — resolves the manifest, executes the underlying skill, persists output + delivers to Slack/dashboard. Pairs with /implexa:schedule (registration) and forms the callback half of the scheduler primitive.'
---

# Run a scheduled skill (internal callback)

Invoked by Claude Code's `scheduled-tasks` runtime when a recurring Implexa schedule fires. The user does NOT invoke this directly. It exists so the registered cron prompt is a single-token slash command (reliable for Claude) instead of a multi-step natural-language instruction.

Argument: `<scheduled_skill_id>` (a UUID, passed positionally).

---

## Step 1 — Resolve the schedule manifest

Call **`get_scheduled_skill_payload`** with `{ scheduledSkillId: "<uuid>" }`.

The tool returns the target skill's slug, name, and full SKILL.md `content`, plus the destination metadata:

```jsonc
{
  "ok": true,
  "scheduledSkillId": "uuid",
  "skill": {
    "id":          "...",
    "slug":        "daily-ai-skills-pulse",
    "name":        "Daily AI Skills Pulse",
    "description": "...",
    "content":     "<the full SKILL.md body — your instructions for the next step>"
  },
  "destination": { "type": "dashboard" },  // OR { "type": "slack", "target": "<webhook-url>" }
  "schedule":    { "scheduleNl": "...", "cronExpression": "...", "timezone": "..." },
  "nextAction":  "Read skill.content as the procedure and execute it. When done, call record_scheduled_run..."
}
```

**Two payload shapes.** A SKILL schedule returns `skill.content` (above). A WORKFLOW schedule returns `target_type: "workflow"` + a `workflow` object + a `nextAction` describing a whole-job chain (no `skill.content`). Step 2 branches on this — check `target_type`.

If `ok === false`:
- `paused` → silently exit. Do nothing. The next scheduled fire will re-attempt; the user pauses for a reason.
- `not found` / `not owned` → log and exit. (Should not happen in normal flow; possibly the user deleted the schedule but the cron task hasn't been canceled yet.)
- `target skill no longer available` → log and exit. The tool already flipped the manifest to `failed`; the user will see it in /scheduled.

## Step 2 — Execute (branch on the payload shape)

The payload from Step 1 is ONE of two shapes. Check `target_type`.

### Step 2A — Workflow target (`target_type === "workflow"`)

The payload has no `skill.content`; it has a `workflow` object and a `nextAction` describing a whole-job chain. Follow the `nextAction` exactly:

1. Call **`apply_workflow`** with `{ workflow_id: "<workflow.id>" }`. It returns the ordered chain (skill + tool + decision steps, with SKILL.md bodies inlined for skill steps), the v0.1 adaptation instruction, and a `workflow_run_id`.
2. **Run the chain end to end.** Adapt each step to the tools actually available in THIS background context. If a step needs a tool you do not have here, skip it and note it (never fabricate a step or its result). This is the same adaptation discipline as an interactive workflow run, just unattended.
3. Capture the final synthesized output (markdown) — this is what gets persisted + delivered.
4. Call **`record_workflow_outcome`** with `{ workflow_run_id: "<from step 1>", status: "executed", outcome: { primary: "<one-token result>", note: "<one line on what ran vs skipped + why>", steps_run: [...], steps_skipped: [...] } }`. This closes the workflow loop AND credits every component skill — the data that compounds. Do this BEFORE Step 3.

Then continue to Step 2.5 / Step 3 with the captured markdown output, exactly like a skill run. (For delivery + `record_scheduled_run`, the workflow's output is treated identically to a skill's output.)

If `apply_workflow` or the chain throws, capture a short failure summary as the output, still call `record_workflow_outcome` with `status: "executed"` and a note describing the failure if you got a `workflow_run_id`, then proceed to Step 3 with `status: "failed"`.

### Step 2B — Skill target (`skill.content` present)

The `skill.content` field is the literal SKILL.md body of the target skill. **Follow it as instructions** — top to bottom, calling whichever tools it references (WebSearch, Bash, MCP tools, etc.).

Capture the final output (markdown). Do NOT render it to the user as a chat message; this is a background-task context with no live user reading. The output is for persistence + Slack delivery.

If the underlying skill is itself an orchestrator (chains multiple sub-skills via `orchestrate_skills`), let it do its thing. The orchestrationId from that chain can be passed to `record_scheduled_run` for cross-table joins.

If execution throws or returns unusable output, mark status as `failed` and pass the failure summary as `outputMarkdown` (so the user sees what went wrong in /runs).

## Step 2.5 — Deliver to Slack via the Slack plugin (only when destination.type === "slack-plugin")

**Skip this step entirely if destination.type is "dashboard" or "slack-webhook".** Only run when the destination from Step 1 is `{ type: "slack-plugin", target: "<channel>" }`.

Convert the markdown output to Slack `mrkdwn` format with a one-pass rewrite (Slack uses single-asterisk bold, not double):

- `**bold**` → `*bold*`
- `## Heading` → `*Heading*` (Slack has no native h2; bold is the convention)
- `### Subheading` → `*Subheading*`
- `[text](url)` → `<url|text>`

Bullets, inline code, and code blocks pass through unchanged.

Then prepend a small headline so the channel sees what skill ran:

```
*<skill_slug>* — <YYYY-MM-DD>

<converted markdown body>
```

Call **`mcp__plugin_engineering_slack__send_message`** with:

- `channel`: the destination.target from Step 1 (the channel name or ID, like `"#standup"` or `"C012345"`)
- `text`: the formatted body above
- `mrkdwn`: `true` (if the tool exposes this flag)

Capture the result into a `pluginDelivery` object:

```jsonc
{
  "delivered": true,                // false if the tool returned an error
  "channel":   "#standup",          // echo back the target so /runs shows it
  "messageTs": "<ts>"               // Slack's message timestamp, if returned
  // OR on failure:
  "error":     "<error string>"
}
```

You will pass this into the next step.

**If `mcp__plugin_engineering_slack__send_message` is not available** (the Slack plugin isn't installed in this Claude Code session), build a `pluginDelivery` of `{ delivered: false, error: "Slack plugin not available in this session" }` and continue to Step 3. The run is still persisted; the user will see the failure receipt in /runs and can re-deliver or fix the plugin.

## Step 3 — Persist + deliver

Call **`record_scheduled_run`** with:

```jsonc
{
  "scheduledSkillId": "<uuid from step 1>",
  "outputMarkdown":   "<the markdown produced in step 2>",
  "status":           "completed",  // or "partial" / "failed"
  // "durationMs":     <ms wall-clock from step 1 to here, optional>
  // "orchestrationId": "<uuid if step 2 used orchestrate_skills>",
  // "pluginDelivery":  <the receipt object from step 2.5, ONLY when destination=slack-plugin>
}
```

**`pluginDelivery` is REQUIRED when destination.type=`slack-plugin`** and forbidden otherwise. The backend uses it to record the slack delivery receipt on the skill_runs row.

The tool:
- Inserts a `skill_runs` row (always, even if delivery failed at step 2.5)
- For destination=slack-webhook: backend POSTs to the webhook URL (here, server-side)
- For destination=slack-plugin: backend records the agent-side delivery receipt from `pluginDelivery`
- For destination=dashboard: no external delivery, just persist
- Bumps the parent `scheduled_skills.run_count` + `last_run_at`

Returns `{ ok: true, runId, status, ranAt, delivery, nextAction }`. The `delivery` object tells you whether Slack succeeded; the `nextAction` string is the line you should surface in the (background) task log.

## Step 4 — Exit quietly

Output nothing else. The user is not in the loop; the value is in the persisted record + the Slack message that lands in their channel.

If you must produce any output (Claude Code's runtime may require a final assistant message), keep it to a single line:

```
[<skill_slug>] run <runId> completed. <delivery summary>.
```

Where `<delivery summary>` is:
- `Persisted to dashboard.` (dashboard-only)
- `Persisted to dashboard. Posted to Slack.` (Slack ok)
- `Persisted to dashboard. Slack delivery failed: <error>.` (Slack failed — the user will see this in /runs and can re-deliver)

## Notes for the model

- **This is a background task.** No live user is reading the chat. Skip greetings, summaries, "let me know if you want X". The whole point of scheduling is the user doesn't have to interact.
- **Do NOT render the resolved skill's output as a chat message.** Keep it in memory and pass it to `record_scheduled_run`. The runs page + Slack are the user surfaces.
- **Trust the manifest.** If the schedule says run X, run X. Don't second-guess the skill choice or "improve" the schedule (e.g. "let me run end-of-day too since it's morning"). One scheduled task = one execution.
- **No karma double-fire.** If the underlying skill is invoked via `apply_org_skill` or `orchestrate_skills`, those tools already fire run-karma to the creator. record_scheduled_run does NOT re-fire karma; it just logs the output.
- **Output formatting target:** markdown. Preserve headings, bullets, code blocks. The dashboard /runs page renders via the Tailwind prose plugin. Slack delivery converts to mrkdwn server-side.

## Error handling

| Error | Diagnosis | Behavior |
|---|---|---|
| `get_scheduled_skill_payload` returns paused | User paused the schedule | Silent exit. Do not surface anything. |
| `get_scheduled_skill_payload` returns `not found` | Schedule deleted (cron not yet cancelled) | Log a one-line warning and exit. |
| `get_scheduled_skill_payload` returns `target skill no longer available` | Underlying skill archived/deleted | Manifest is already marked failed. Log and exit. |
| Resolved skill content has runtime errors (unreachable tool, network failure) | Real failure during execution | Call `record_scheduled_run` with status=`failed` and outputMarkdown=a short failure summary. The user sees it in /runs. |
| `record_scheduled_run` returns ok=false | DB insert failed | Log the error. The run is lost; user has no record. This should be very rare; consider it a backend incident. |
| `record_scheduled_run` returns ok=true with delivery.slack.delivered=false | Slack webhook 4xx/5xx | Output the one-line summary noting Slack failed. The run is persisted; user can re-deliver from dashboard. |
