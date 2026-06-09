---
description: 'Save a multi-step job the user just did by hand as a reusable, schedulable AGENT. Reconstruct the SHAPE of what happened this session (the ordered steps + tool kinds + decision logic, never the user''s real names/numbers/handles/row data), save it via capture_workflow, then offer to put it on a schedule and to share it. Use when the user says "save this", "save what we just did", "make that an agent", "turn what we just did into an agent", "save the whole flow", "remember this for next time", or invokes /implexa:record. This is how a one-off becomes an agent the user can re-run or schedule, without rebuilding it by hand. (The old live-demonstration / interview recording paths are retired; agents are built from the session trace or from a plain-language description via the build flow.)'
---

# Save what you just did as an agent

The user did a whole job by hand this session and wants it saved as something they
can re-run or schedule, not a one-off. You save the SHAPE of the job as an agent.

**Shape-only, always.** Save the chain + the tool kinds + the decision logic.
NEVER the user's actual company names, numbers, handles, or row data. An agent is
a reusable template, not a record of one private run. Any step that touched a real
client/customer becomes a `decision` approval gate, not an unattended send.

## Step 1, confirm the job in one generic line

Ask: *"In one sentence, what whole job does this do?"* Phrase it generically, as a
reusable template, not this one run: *"produce my daily IG reel end to end"*,
*"build a competitor brief before a sales call"*, *"warm up a renewal account"*.

If they give a vague answer ("some research"), push back once: *"Can you say it
more specifically, what's the goal?"*

## Step 2, reconstruct the ordered steps from the session trace

From your own memory of what you actually ran this session, list the steps in
order. For each:

- `order`: 1-based position.
- `kind`: `skill` | `tool` | `decision`.
- `ref`: for a **skill** step, the `{ source, slug }` you applied (from the
  `apply_*` call that ran it); for a **tool** step, `{ tool: "<mcp tool name>" }`;
  for a **decision**, `{ rule: "<the branch / approval logic>" }`.
- `label`: one generic line of what the step does.

Strip ALL specifics. Don't pad, if the job was 4 real steps, save 4. A single
short procedure is fine too, save it as a 1-2 step agent.

## Step 3, name, slug, vertical

- `name`: 2-5 words ("daily IG reel produce + render").
- `slug`: lowercase-hyphen, unique (the tool rejects a collision, pick another if
  so).
- `vertical`: the domain ("creator", "sales", "developer", "recruiter").

## Step 4, save it

Call **`capture_workflow`** with `{ intent, vertical, name, slug, steps,
description? }`. It saves the agent privately to the user (owned by them),
unproven until real runs harden it. Show them the saved agent's URL + the step
count.

## Step 5, offer to schedule, then offer to share

- **Schedule** (offer always): *"want this to run on its own? i can put it on a
  schedule."* If yes: first, if the agent declared any config, resolve it now via
  `get_workflow_setup` → ask the questions → `save_workflow_setup`, so the
  unattended run is hands-free. Then call `schedule_skill({ skillSlug: "<slug>",
  source: "community", scheduleNl: "<their pick>" })`, then
  `mcp__scheduled-tasks__create_scheduled_task` with the returned
  `claudeScheduledTaskPrompt` / `cronExpression` / `timezone`. Confirm in ≤2 lines:
  *"scheduled. runs <humanizedSchedule>. output lands at app.implexa.ai/runs."*

- **Share** (opt-in ONLY, never pushy): *"want to share this with the community?
  i'll strip any personal details and make it generic, and you earn karma."* If
  yes → genericize the name/description so there's no PII, then call
  `share_workflow({ slug: "<slug>", source: "community", name, description })`.
  Never share without an explicit yes.

## What's next?

- `Put this agent on a schedule`
- `Share this agent with my team`
- `Show me the other agents I've saved`

## Notes for the model

- **Shape, not data.** The single most important rule. Strip every real name,
  number, handle, and row. Real client/customer touches become approval-gate
  `decision` steps, never unattended sends.
- **Don't pad the trace.** If the user ran 2 tool calls, save a 2-step agent.
  Forcing 5 steps when 2 happened produces a worse agent.
- **One job per agent.** If the user did three unrelated jobs this session, ask
  which one to save and offer to save the others separately.
- **The schedule offer is where a one-off becomes a habit.** Most users don't know
  they can schedule it. Offer it at the moment of save.
- **Voice rules apply.** Lowercase, plain, no em-dashes anywhere.

## Error handling

| Error from a tool | Diagnosis | Tell the user |
|---|---|---|
| `slug already exists` from capture_workflow | slug collision | pick another slug and retry; suggest one from the name. |
| `schedule_skill` fails (bad parse / unknown agent) | the cadence didn't parse | surface the error, offer to retry with a different cadence. Don't block the rest of the save flow. |
| `mcp__scheduled-tasks__create_scheduled_task` unavailable | scheduled-tasks runtime not in this session | the agent is still saved; tell the user they can run `/implexa:run-scheduled <id>` manually or schedule from the dashboard. |
