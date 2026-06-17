---
description: 'Internal callback agent invoked by Claude Code''s scheduled-tasks runtime when a recurring Implexa schedule fires. Use ONLY when Claude is dispatched via a scheduled task with a prompt like "/implexa:run-scheduled <uuid>" - humans should not invoke this directly. THE Implexa scheduler execution path - resolves the manifest, executes the underlying agent, persists output + delivers to Slack/dashboard. Pairs with /implexa:schedule (registration) and forms the callback half of the scheduler primitive.'
---

# Run a scheduled agent (internal callback)

Invoked by Claude Code's `scheduled-tasks` runtime when a recurring Implexa schedule fires. The user does NOT invoke this directly. It exists so the registered cron prompt is a single-token slash command (reliable for Claude) instead of a multi-step natural-language instruction.

Argument: `<scheduled_skill_id>` (a UUID, passed positionally). An optional second token `--on-demand` marks an EXPLICIT on-demand fire (the user triggered "run now" from the dashboard / phone / Telegram via a one-time task), as opposed to the recurring cron firing on its own. It changes one thing in Step 1 (paused agents run).

---

## Step 0 - FIRST ACTION: open the in-flight run record (before ANYTHING else)

The very first tool you call MUST be **`record_run_start`** with
`{ scheduledSkillId: "<the uuid from the argument>" }`. Keep the returned
`runId`.

**Do NOT run any other tool before this - especially not Bash.** Do not "orient",
do not list directories, do not check the day number, do not probe tooling. You
already have the uuid from the argument; record the start with it, THEN resolve
the manifest (Step 1).

Why this is non-negotiable: a scheduled run executes unattended. If an early
tool (e.g. an exploratory `find` in Bash) raises a permission prompt, there is
no one to answer it and the run dies ("permission stream closed") - and if that
happens before this record exists, the run leaves NO trace: not in Needs-you,
not flagged stalled, invisible (the exact failure the founder hit on the daily
IG reel). With the row open FIRST, even an immediate crash leaves a `running`
row the watchdog flips to `stalled`, so the desktop buzzes and Needs-you shows
it. Recording first is what makes a dead run visible.

If `record_run_start` itself fails (offline/transient), proceed anyway and omit
`runId` in Step 3 - never block the work on telemetry.

## Step 1 - Resolve the schedule manifest

Call **`get_scheduled_skill_payload`** with `{ scheduledSkillId: "<uuid>" }`.

**If you were invoked with `--on-demand`**, call it with `{ scheduledSkillId: "<uuid>", allowPaused: true }` instead. An explicit on-demand fire must run the agent even if its routine is PAUSED — pause only stops the automatic cron, never an explicit "run now". This does NOT change the agent's status: a paused agent runs this once and stays paused (the one-time task auto-disables; you do not resume or re-pause anything). Without `--on-demand`, a paused agent returns `status: "paused"` below and you exit quietly — a paused routine's cron must never auto-run.

The tool returns the target agent's slug, name, and full SKILL.md `content`, plus the destination metadata:

```jsonc
{
  "ok": true,
  "scheduledSkillId": "uuid",
  "skill": {
    "id":          "...",
    "slug":        "daily-ai-skills-pulse",
    "name":        "Daily AI Skills Pulse",
    "description": "...",
    "content":     "<the full SKILL.md body - your instructions for the next step>"
  },
  "destination": { "type": "dashboard" },  // OR { "type": "slack", "target": "<webhook-url>" }
  "condition":   null,                       // OR an only-when gate string (see Step 1.4)
  "schedule":    { "trigger": "cron", "scheduleNl": "...", "cronExpression": "...", "fireAt": null, "condition": null, "timezone": "..." },
  "nextAction":  "Read skill.content as the procedure and execute it. When done, call record_scheduled_run..."
}
```

**Two payload shapes.** A skill-type schedule returns `skill.content` (above). A workflow-type schedule returns `target_type: "workflow"` + a `workflow` object + a `nextAction` describing a whole-job chain (no `skill.content`). Step 2 branches on this - check `target_type`.

`schedule.trigger` tells you HOW this routine fires: `"cron"` (recurring clock, the default), or `"once"` (a one-time fireAt run - handle Step 3.6 after recording). `condition` (top-level, mirrored at `schedule.condition`) is an optional only-when gate - handle Step 1.4 BEFORE doing any work.

If `ok === false`:
- `paused` → silently exit. Do nothing. The next scheduled fire will re-attempt; the user pauses for a reason.
- `not found` / `not owned` → log and exit. (Should not happen in normal flow; possibly the user deleted the schedule but the cron task hasn't been canceled yet.)
- `target skill no longer available` → log and exit. The tool already flipped the manifest to `failed`; the user will see it in /scheduled.

## Step 1.3 - Honor prior feedback (the improvement loop)

The payload carries `recentFeedback`: the user's answers to this agent's earlier runs (each `{ questions, answers }`). It has already been marked consumed, so use it NOW, this run:
- Adjust how you produce this run's output to honor what the user said (they said the hook was weak → open stronger; they said too long → tighten).
- `answers` may include a `_freeform` key: the user's own free-text comment, written outside your pre-filled questions. Treat it as the highest-signal feedback — it is what they chose to say unprompted. Honor it even when it has nothing to do with the questions you asked.
- When the feedback implies a DURABLE change to the agent (not just this run), call **`propose_workflow_revision`** with the improved steps so the agent permanently gets better. That revision surfaces in the agent's "Improved this week" card.

If `recentFeedback` is empty, skip this step.

## Step 1.4 - Condition gate (only when `condition` is set)

**Skip this step entirely if `condition` (and `schedule.condition`) is null/absent.** Most routines have no gate; go straight to Step 1.5.

When `condition` is a non-empty string, this is a CRON routine with an only-when gate (e.g. `"a new file named RAW appears in my Drive"`). The clock fired, but the user only wants the actual work done WHEN the condition holds. So evaluate it FIRST, before running anything:

1. **Check the condition** using whatever read-only tools it implies - list the Drive folder, GET the page, query the inbox, etc. Use only tools already in the pre-approved manifest (Step 1.5); if you cannot check it without an un-granted tool, treat that like any blocked tool (record a `failed` run naming the missing tool, per Step 1.5).
2. **If the condition is NOT met:** this fire is a no-op. Do **not** run the agent, do **not** fabricate output, and do **not** record a run - just exit quietly (same as the `paused` case). The next scheduled fire will check again. The whole point of the gate is that an unmet fire produces nothing.
3. **If the condition IS met:** continue to Step 1.5 / Step 2 and run normally.

This gate is what makes "check every day, but only process it when X" correct: without it, a plain cron would run the work every day regardless. Never run the body on an unmet condition - that is the exact wrong behavior the gate exists to prevent.

## Step 1.5 - The permission manifest (silence must never read as success)

A workflow payload now carries **`permission_manifest`** - the tools + fetch domains this agent was pre-approved for at schedule time (`/implexa:schedule` Step 2.7). You do not need to act on it to run; the pre-grant already wrote the allowlist. It matters for ONE thing: how you handle a tool that is **denied**.

This run executes under the scheduled-run permission scope, which uses `defaultMode: "dontAsk"`. That means a tool NOT in the pre-approved allowlist is **denied and you keep going** (it does not prompt and does not hang, the old silent-stall trap). When that happens:

- **Do NOT silently skip it and report success.** A denied tool that was load-bearing for the deliverable is a FAILURE, not a clean run.
- Note which tool was blocked. If the deliverable cannot be produced without it, set the run `status: "failed"` in Step 3 and make `outputMarkdown` a short, specific line: `Blocked on a permission not pre-approved: <tool/domain>. Re-grant it by re-running /implexa:schedule for this agent (it will pre-approve the updated manifest).`
- If the blocked tool was non-essential (an optional enrichment) and the core deliverable still came out, record `status: "partial"` and note the skipped tool in the output, never a bare "completed".

The dashboard reads run state, so a `failed`/`partial` run with this reason surfaces as a visible, one-tap-fixable problem instead of an agent that appears to have never run.

## Step 1.7 - Heartbeat + step trace

You already opened the in-flight run record in Step 0. At **each major step
boundary** call **`record_run_heartbeat`** with that `runId` AND a short `note`
of what you just did or are about to do (e.g. `note: "step 3/7: submitting
sitemap to Search Console", step: "3/7"`). Two reasons:

1. It keeps a slow-but-alive run from being mistaken for stalled (the original purpose).
2. The `note` builds the run's **live step trace**, shown on the run page. This is
   what makes a stall legible: if this agent hangs, the user (and a phone watching
   the run) sees exactly which step it died on instead of a bare "stalled" — the
   gap the founder hit when a run stuck and nothing could say where.

So: heartbeat-with-note liberally, at least once per real step. Cheap and free.
If Step 2 uses orchestrate_skills, you can pass its `orchestrationId` to
`record_scheduled_run` in Step 3 for cross-table joins.

## Step 2 - Execute (branch on the payload shape)

**Where to write files.** Any file this run produces or needs as scratch (a draft, a render, a log, a downloaded asset, a `package.json` for a render project) MUST go under **`~/Implexa Agents/<skill_slug>/`** — create it with `mkdir -p` first. Do NOT write to `/tmp` or into a code repo: those paths trip Claude Code's working-directory gate and stall an unattended run. `~/Implexa Agents` is pre-granted, so writes there never prompt, and the user gets one tidy place for every agent's output. Read inputs from wherever they live, but write outputs only here.

The payload from Step 1 is ONE of two shapes. Check `target_type`.

### Step 2A - Workflow target (`target_type === "workflow"`)

The payload has no `skill.content`; it has a `workflow` object and a `nextAction` describing a whole-job chain. Follow the `nextAction` exactly:

1. Call **`apply_workflow`** with `{ workflow_id: "<workflow.id>" }`. It returns the ordered chain (agent steps + tool steps + decision steps, with SKILL.md bodies inlined for agent steps), the v0.1 adaptation instruction, and a `workflow_run_id`.
2. **Run the chain end to end.** Adapt each step to the tools actually available in THIS background context. If a step needs a tool you do not have here, skip it and note it (never fabricate a step or its result). This is the same adaptation discipline as an interactive workflow run, just unattended.
3. Capture the final synthesized output (markdown) - this is what gets persisted + delivered.
4. Call **`record_workflow_outcome`** with `{ workflow_run_id: "<from step 1>", status: "executed", outcome: { primary: "<one-token result>", note: "<one line on what ran vs skipped + why>", steps_run: [...], steps_skipped: [...] } }`. This closes the workflow loop AND credits every component agent - the data that compounds. Do this BEFORE Step 3.

Then continue to Step 2.5 / Step 3 with the captured markdown output, exactly like an agent run. (For delivery + `record_scheduled_run`, the workflow output is treated identically to an agent's output.)

If `apply_workflow` or the chain throws, capture a short failure summary as the output, still call `record_workflow_outcome` with `status: "executed"` and a note describing the failure if you got a `workflow_run_id`, then proceed to Step 3 with `status: "failed"`.

### Step 2B - Agent target (`skill.content` present)

The `skill.content` field is the literal SKILL.md body of the target agent. **Follow it as instructions** - top to bottom, calling whichever tools it references (WebSearch, Bash, MCP tools, etc.).

Capture the final output (markdown). Do NOT render it to the user as a chat message; this is a background-task context with no live user reading. The output is for persistence + Slack delivery.

If the underlying agent is itself an orchestrator (chains multiple sub-agents via `orchestrate_skills`), let it do its thing. The orchestrationId from that chain can be passed to `record_scheduled_run` for cross-table joins.

If execution throws or returns unusable output, mark status as `failed` and pass the failure summary as `outputMarkdown` (so the user sees what went wrong in /runs).

## Step 2.5 - Deliver to Slack via the Slack plugin (only when destination.type === "slack-plugin")

**Skip this step entirely if destination.type is "dashboard" or "slack-webhook".** Only run when the destination from Step 1 is `{ type: "slack-plugin", target: "<channel>" }`.

Convert the markdown output to Slack `mrkdwn` format with a one-pass rewrite (Slack uses single-asterisk bold, not double):

- `**bold**` → `*bold*`
- `## Heading` → `*Heading*` (Slack has no native h2; bold is the convention)
- `### Subheading` → `*Subheading*`
- `[text](url)` → `<url|text>`

Bullets, inline code, and code blocks pass through unchanged.

Then prepend a small headline so the channel sees what agent ran:

```
*<skill_slug>* - <YYYY-MM-DD>

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

## Step 2.6: Post-run action (only when the payload has `post_run_action`)

**Skip this step entirely if `post_run_action` is null/absent.** It exists so the routine prompt can stay a thin `/run-scheduled <id>` shim: any side-effecting publish step lives as structured config on the schedule, not as hand-written prose in the cron prompt. When the workflow improves, nothing here changes.

The only v1 shape is `{ "type": "publish-content", "repo": "<abs path>", "script": "scripts/publish-draft-post.mjs", "artifact_path": "/tmp/implexa-seo.md" }` (script + artifact_path may be omitted; use those defaults).

Do this:

1. **Decide the publish branch from the workflow's chosen action** (the workflow output from Step 2A tells you which it picked):
   - **new article** → no `--edit`. The deliverable is a full new post (frontmatter + body).
   - **title/meta rewrite** or **page expansion** → `--edit --path <repo-relative target file>`. The deliverable is the FULL edited existing file; the target path is the existing page the agent chose (e.g. `content/blog/<slug>.md` or `content/resources/<slug>.md`).
2. **Write the deliverable** to `post_run_action.artifact_path` (default `/tmp/implexa-seo.md`), exactly as the publisher expects (valid frontmatter, no em-dashes, the agent's full output).
3. **Run the gated publisher** from the repo, via Bash, building the command from the structured fields (never run an arbitrary stored string):
   - new article: `node <repo>/<script> <artifact_path> --merge`
   - edit: `node <repo>/<script> <artifact_path> --edit --path <target> --merge`
   where `<script>` defaults to `scripts/publish-draft-post.mjs`.
4. **Read the exit code** and capture a one-line publish result to fold into the run output:
   - `0` → opened + merged (live). 
   - `1` → a content gate failed: READ the error, fix the deliverable, re-run, max 2 retries.
   - `2` → git/gh failure (note it).
   - `3` → PR opened but NOT merged (a check failed or did not finish); leave it for a human and note the PR URL.
   Never merge by hand past a red check.
5. Append the publish result (action taken + exit outcome + PR URL) to the markdown you pass to Step 3, so `/runs` records what shipped.

If `post_run_action.repo` does not exist on this machine, or `node`/the script is unavailable in this background context, skip the publish, note `"publish skipped: <reason>"` in the output, and continue to Step 3 (the run is still recorded; the user can publish by hand). Never fabricate a publish result.

## Step 2.6 - Lock onto a browser session FIRST (never wait for "1, 2, or 3")

If Step 2 drives the browser (any `mcp__claude-in-chrome__` / `mcp__Claude_in_Chrome__` tool), SELECT the session up front, before the first navigate/read — otherwise the Chrome MCP stops and asks which connected session to use, and an unattended run has no one to answer, so it stalls (the exact silent-stall trap). Do this once at the start of the browser work:

1. Call **`list_connected_browsers`** to enumerate the connected Chrome sessions.
2. Pick ONE, in this order:
   - the **dedicated Implexa workspace profile** ("Implexa Claude Chrome Connect") if present — it's where the agent's signed-in accounts live;
   - else the session that already has the **target site** (the domain this step needs) open;
   - else the **first** connected session.
3. Call **`select_browser`** (or `switch_browser`) to lock onto it, THEN do the browse work.

Never present the user a "1, 2, or 3" choice or wait on it — you choose, deterministically, with the order above. If `list_connected_browsers` returns nothing, treat it as the browser not being connected (degrade per Step 2.7).

## Step 2.7 - Runtime reachability (degrade honestly, then record the unreachable account)

A browser-driving agent signs into the user's real accounts (Gmail, a CRM, a calendar) through the paired Chrome profile. At run time an account that was reachable at schedule time can be unreachable now: signed out, the profile's session expired, the wrong Claude-account binding, or it was never connected. The reliability rule is the same as the permission rule in Step 1.5: **silence must never read as success.**

This step applies whenever Step 2 needed a signed-in account and could not reach it. It is separate from a denied permission (Step 1.5): there the *tool* is blocked; here the tool ran but the *account it drives* is not reachable.

1. **Degrade honestly via the existing fallback.** Reachability tries the dedicated profile first, then the main profile as best-effort backup. If BOTH are unreachable for a required account, the account is unreachable for this run. Do not paper over it with a plausible-looking empty result (e.g. "no new emails today" when the inbox was never opened).

2. **Decide the status by load-bearing-ness:**
   - The unreachable account was REQUIRED for the deliverable (e.g. the inbox the agent summarizes) → `status: "failed"`.
   - The core deliverable still came out and the unreachable account was a secondary source → `status: "partial"`.
   Never record a bare `"completed"` when a required account could not be reached.

3. **Record the unreachable account** so both the dashboard Connections section AND the run-state surface show it. Collect each one and pass it to `record_scheduled_run` in Step 3 as `unreachableAccounts` (see the shape there). The backend fans this out: it stamps the `skill_runs` row (run-state) and upserts the account as `unreachable` in the Connections registry (so Connections shows the red marker without waiting for the desktop to re-verify).

4. **Make the output specific.** `outputMarkdown` should name the account and the fix, e.g.: `Could not reach <account> in any paired Chrome profile, so this run is incomplete. Sign it into your dedicated Implexa profile (app.implexa.ai/connections), then it will run clean next fire.`

## Step 3 - Persist + deliver

Call **`record_scheduled_run`** with:

```jsonc
{
  "scheduledSkillId": "<uuid from step 1>",
  "runId":            "<the runId from record_run_start in Step 0>",
  "outputMarkdown":   "<the markdown produced in step 2>",
  "status":           "completed",  // or "partial" / "failed"
  // "durationMs":     <ms wall-clock from step 1 to here, optional>
  // "orchestrationId": "<uuid if step 2 used orchestrate_skills>",
  // "pluginDelivery":  <the receipt object from step 2.5, ONLY when destination=slack-plugin>
  // "unreachableAccounts": [   // ONLY when Step 2.7 hit an unreachable account; omit otherwise
  //   { "kind": "account", "identifier": "rabi@implexa.ai", "reason": "not signed in to any paired profile" }
  // ],
  "feedbackQuestions": [   // 2-3 SHORT questions about THIS output, so the user can improve the agent
    { "key": "hook_strong",  "question": "Was the hook strong enough?", "kind": "choice", "options": ["Yes", "No"] },
    { "key": "length",       "question": "How was the length?",         "kind": "choice", "options": ["Too short", "Just right", "Too long"] },
    { "key": "change",       "question": "Anything to change next time?", "kind": "text" }
  ]
}
```

**`feedbackQuestions`** (include on every `completed`/`partial` run) is the improvement loop. Write 2-3 questions FROM the actual deliverable you just produced, so they are relevant to it (a reel asks about the hook + style; a market report asks if the top metric was the right one; a lead list asks if the targeting fit). Prefer `kind: "choice"` with 2-3 options for one-tap answering; include at most one `kind: "text"` "anything to change?" question. The user answers them on the dashboard, and their answers come back to you as `recentFeedback` on the NEXT run (Step 1.3) so the agent improves itself. Omit only when the output is purely informational with nothing worth rating.

**`pluginDelivery` is REQUIRED when destination.type=`slack-plugin`** and forbidden otherwise. The backend uses it to record the slack delivery receipt on the skill_runs row.

**`unreachableAccounts`** (optional) carries what Step 2.7 found. Include it only when a required account could not be reached; omit the field entirely on a clean run. The backend records it on the `skill_runs` row (run-state) and upserts each account as `unreachable` in the Connections registry, so the dashboard surfaces the gap.

The tool:
- Inserts a `skill_runs` row (always, even if delivery failed at step 2.5)
- For destination=slack-webhook: backend POSTs to the webhook URL (here, server-side)
- For destination=slack-plugin: backend records the agent-side delivery receipt from `pluginDelivery`
- For destination=dashboard: no external delivery, just persist
- Bumps the parent `scheduled_skills.run_count` + `last_run_at`

Returns `{ ok: true, runId, status, ranAt, delivery, nextAction }`. The `delivery` object tells you whether Slack succeeded; the `nextAction` string is the line you should surface in the (background) task log.

## Step 3.6 - Disable a one-time run after it fires (only when `schedule.trigger === "once"`)

**Skip this step unless `schedule.trigger` is `"once"`.** A one-time routine should fire exactly once and then be done.

Claude Code's scheduled-task runtime auto-disables the `fireAt` task on its side after it fires, so it will not fire again. This step keeps the Implexa manifest in sync so the dashboard stops showing the routine as active/pending:

- After `record_scheduled_run` returns, call **`pause_scheduled_skill({ scheduledSkillId: "<uuid from step 1>" }`)**. This flips the manifest to paused so it reads as "ran, done" rather than "still scheduled". Idempotent; a failure here is non-fatal (the run is already recorded) - note it and continue.

Do NOT do this for `cron` routines - they are recurring and must stay active.

## Step 4 - Exit quietly

Output nothing else. The user is not in the loop; the value is in the persisted record + the Slack message that lands in their channel.

If you must produce any output (Claude Code's runtime may require a final assistant message), keep it to a single line:

```
[<skill_slug>] run <runId> completed. <delivery summary>.
```

Where `<delivery summary>` is:
- `Persisted to dashboard.` (dashboard-only)
- `Persisted to dashboard. Posted to Slack.` (Slack ok)
- `Persisted to dashboard. Slack delivery failed: <error>.` (Slack failed - the user will see this in /runs and can re-deliver)

## Notes for the model

- **This is a background task.** No live user is reading the chat. Skip greetings, summaries, "let me know if you want X". The whole point of scheduling is the user doesn't have to interact.
- **Do NOT render the resolved agent's output as a chat message.** Keep it in memory and pass it to `record_scheduled_run`. The runs page + Slack are the user surfaces.
- **Trust the manifest.** If the schedule says run X, run X. Don't second-guess the agent choice or "improve" the schedule (e.g. "let me run end-of-day too since it's morning"). One scheduled task = one execution.
- **No karma double-fire.** If the underlying agent is invoked via `apply_org_skill` or `orchestrate_skills`, those tools already fire run-karma to the creator. record_scheduled_run does NOT re-fire karma; it just logs the output.
- **Output formatting target:** markdown. Preserve headings, bullets, code blocks. The dashboard /runs page renders via the Tailwind prose plugin. Slack delivery converts to mrkdwn server-side.

## Error handling

| Error | Diagnosis | Behavior |
|---|---|---|
| `get_scheduled_skill_payload` returns paused | User paused the schedule | Silent exit. Do not surface anything. |
| `get_scheduled_skill_payload` returns `not found` | Schedule deleted (cron not yet cancelled) | Log a one-line warning and exit. |
| `get_scheduled_skill_payload` returns `target skill no longer available` | Underlying agent archived/deleted | Manifest is already marked failed. Log and exit. |
| Resolved agent content has runtime errors (unreachable tool, network failure) | Real failure during execution | Call `record_scheduled_run` with status=`failed` and outputMarkdown=a short failure summary. The user sees it in /runs. |
| A required signed-in account is unreachable in any paired Chrome profile (Step 2.7) | The account is signed out, expired, or never connected | Degrade honestly. Set status `failed` (required) or `partial` (secondary), name the account + fix in `outputMarkdown`, and pass it in `unreachableAccounts`. Never record a bare `completed`. |
| `record_scheduled_run` returns ok=false | DB insert failed | Log the error. The run is lost; user has no record. This should be very rare; consider it a backend incident. |
| `record_scheduled_run` returns ok=true with delivery.slack.delivered=false | Slack webhook 4xx/5xx | Output the one-line summary noting Slack failed. The run is persisted; user can re-deliver from dashboard. |
