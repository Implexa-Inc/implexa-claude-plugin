---
description: 'Capture a workflow as a structured skill. Three entry intents in one flow: (A) NEW skill via live demonstration, (B) POST-HOC save of work just completed (no demo needed), or (C) UPDATE an existing skill by re-recording. Use when the user says "record a skill", "record this", "watch me do this once", "capture this as a skill", "save this", "save this as a skill", "make that a workflow", "save what we just did", "improve my X skill", "update my X skill by re-recording", "add a step to my Y skill via demo", or invokes /implexa:record. THE killer feature of the Skill Graph — one demonstration becomes a reusable, conditional, measurable skill via a post-hoc structured interview. Absorbs the old /implexa:save-this (now Branch B) and /implexa:update-skill (now Branch C).'
---

# Capture a workflow as a skill (3 intents in one flow)

The user wants to turn a workflow into a structured, reusable skill — properly built (intent + inputs + procedure + decision points + output contract + outcome signal), not just a saved prompt. Three intents trigger this flow; pick the right branch upfront.

## Phase 0 — Which entry intent?

Detect from the user's phrasing and pick one of three branches. Ask only when truly ambiguous.

| User said | Branch | What it does |
|---|---|---|
| "record a skill", "watch me do X", "capture this workflow", "I'll demonstrate this once" | **A — new via demo** | Start a fresh demonstration recording, then interview + finalize as a new skill. |
| "save this", "save what we just did", "make that a skill", "remember this for next time", "turn this into a workflow" | **B — post-hoc save** | No live demo needed; reconstruct the workflow from the existing session trace and save via `capture_workflow_as_skill`. |
| "update my X skill", "improve my Y skill", "add a step to my Z via demo", "re-record my prospecting skill" | **C — update existing via re-record** | Identify the target skill, start a recording for the NEW behavior only, finalize with `replacingSkillId` so Haiku merges the demo into the existing SKILL.md. |

Branches A and C share Phases 1-3 (start recording, observe, interview, finalize) with one difference at finalize (Branch C passes `replacingSkillId`). Branch B is shorter — skip to "Branch B — Post-hoc capture" below.

Ambiguous case (*"record a skill that adds a step to X"*) → ask:

> *"Is this a fresh new skill (A), a save of what we just did (B), or a re-record into an existing one (C)?"*

---

## Branch B — Post-hoc capture (save what we just did)

The user already did the work; they just want it saved as a skill. Skip the live demonstration. Reconstruct the workflow from the session trace and call `capture_workflow_as_skill` directly.

### Step B1 — Confirm the user's INTENT in one sentence

This is the most important step. The captured trace tells us WHAT was done; only the user can tell us WHY. Ask:

> *"In one sentence, what were you trying to accomplish?"*

Examples of good intent:
- *"Warm up an enterprise customer who's up for renewal in 90 days."*
- *"Find candidates for a Bullhorn job order that came in this morning."*
- *"Build a competitive landscape brief for a target company before a sales meeting."*

If they give a vague answer ("doing some research"), push back ONCE: *"Can you say it more specifically — what's the goal?"*

### Step B2 — Propose a skill name

Take the intent and propose 2-5 words, action-flavored (e.g. "Warm up enterprise renewal", "Fill this Bullhorn role"). Confirm with the user; offer 2-3 alternatives if they don't like the first.

### Step B3 — Build inputs from the session trace

Before calling the tool, reconstruct from your own memory of the session:

- `name`: confirmed in B2
- `intent`: confirmed in B1
- `toolsUsed`: distinct MCP tool names you called this session (deduplicate)
- `traceShape`: ordered tool-name sequence
- `traceSummary`: ONE PARAGRAPH narrative — what you did, in what order, and why each step. This is what Haiku uses most when authoring the SKILL.md.
- `exampleArgs`: 2-4 specific arg values that illustrate the workflow shape (will be PII-scrubbed)

Be honest in `traceSummary`. If you tried something that didn't work and pivoted, include it — the skill author may render it as a fallback step.

### Step B4 — Call capture_workflow_as_skill

Call **`capture_workflow_as_skill`** with the B3 inputs. Default `scope: "org"` and `activate: false` (creates as draft). Show the user the `contentPreview` (first 800 chars) from the response.

### Step B5 — Confirm activation + offer schedule + offer share

Ask: *"Activate this for everyone in your org?"* — flip status if yes.

Then jump to Phase 3, Step 3f.5 (offer to schedule) and Step 3g (offer to share). Same flow as Branches A/C from finalize onward.

### Notes for Branch B

- **Don't write the SKILL.md yourself.** The tool calls Haiku — drift-prone if you author manually, and you'll skip PII scrubbing.
- **PII is auto-scrubbed.** If the `scrubReplacements` field is non-empty, mention it: *"I scrubbed N email addresses before saving."*
- **Don't pad the trace.** If the user only ran 2 tool calls, save a 2-tool skill. Forcing 5 steps when 2 happened produces a worse skill.
- **One workflow per skill.** If the user did three unrelated workflows, ask which one to save and offer to save the others separately.

---

## Branches A + C — Live demonstration (continue to Phase 1)

If you're on Branch A (new) or Branch C (update existing via re-record), continue below. Branch C has one extra step before Phase 1 — identify the target skill — and one extra arg at finalize (`replacingSkillId`).

### If updating an existing skill (Branch C only)

1. **Identify the target skill**. If the user named it ("update my HN drafter"), call `list_org_skills` with `query: "<user's words>"` and `createdByMe: true` to find the match. If multiple hits, show a numbered list and have the user pick. Capture the resulting `skillId`.

2. **Confirm with the user before recording starts**:

   > *"Updating `<skill name>` (v<X>). When you finish demonstrating, I'll replace the existing SKILL.md content with this new recording. The old version is preserved in skill history — easy to roll back if needed. Ready?"*

3. **Remember the skillId** — you'll pass it to `interview_for_skill` at finalize as `replacingSkillId`.

4. Continue to Phase 1 with `initialIntent` framed as the UPDATE goal (not the original skill's intent), e.g. *"add inline-posting step via Chrome MCP to the HN comment drafter"*.

### Why this branch matters

The text-edit path (`update_org_skill`) is great for typos, renames, copy polish, and restructuring — but for **adding new procedural steps that call new tools**, it's risky. Claude has to *imagine* what the step should be from your verbal description. The re-record path captures the REAL tool sequence from a live demonstration, so the resulting skill is grounded in observed behavior — not LLM-authored guesswork.

Use re-record when the change involves: new tool calls, new branches, new decision points, new error handling that needs to be validated. Use text edit (`update_org_skill`) when the change is: a typo, a rename, a copy tweak, or a structural reorg of existing content.

## Phase 1 — Start the recording

Before they begin the work, ask **one** question if not already obvious:

> *"In one sentence, what are you about to demonstrate?"*

Then call **`start_demonstration`** with:
- `initialIntent`: the one-sentence answer
- `proposedName`: a slug-friendly suggested name from the intent (e.g. "warm-up-enterprise-renewal")
- `sessionId`: the current session ID

Confirm to the user: *"Recording. Just do your work normally — every external-data tool I run will be logged. Tell me when you're done."*

## Phase 2 — Let the user work

This is the **observation phase**. Do exactly what the user asks. Run whatever tools they need. Three capture surfaces are running simultaneously:

1. **external-data tool calls** — automatic. Every Implexa MCP tool you invoke is appended to the demo trace via the session logger. You don't have to do anything.
2. **Non-Implexa actions** — manual. Any time you use a non-external-data tool (WebSearch, Read, Bash, Write, browser MCP, computer-use, anything outside the Implexa surface), or the user pastes data, or you make a non-obvious decision in your head — call **`record_demo_note`** with a one-sentence summary BEFORE continuing. Example: `record_demo_note({toolName: "web_search", noteText: "Searched G2 for competitor pricing on Snowflake."})`. Silent no-op if no recording active, so safe to call defensively.
3. **Host-forwarded transcript** — automatic if the user has the Implexa hooks installed in `~/.claude/settings.json`. Every user prompt and assistant response gets forwarded to the backend and stored on the demo. Nothing you need to do.

**Do NOT**:
- Tell the user what to do next (let them lead)
- Run extra tools "for completeness" (they'll dilute the skill)
- Add commentary about "this would make a great skill" (annoying)
- Skip `record_demo_note` for non-Implexa actions — without it the resulting skill won't reflect what you actually did

**Do**:
- Execute their requests precisely
- Call `record_demo_note` after WebSearch / file reads / bash / manual reasoning steps
- If you make a non-obvious decision (e.g. choosing one data source over another), briefly note WHY in your response AND in a `record_demo_note` — those notes become decision points in the resulting skill

When the user signals they're done ("ok done", "that's it", "save it", "stop recording"), move to Phase 3.

## Phase 3 — End recording, capture free-text, run the interview, finalize

### Step 3a — End the recording

Call **`end_demonstration`** with the demoId from Phase 1. The system moves the demo into 'interviewing' status and the response tells you what to do next (it'll include `promptForFreeText: true`).

### Step 3b — (Conditional) capture out-of-Claude context

Skip this step in most cases. The host hooks (UserPromptSubmit + Stop + PostToolUse) already capture every prompt, every response, and every tool call during recording — so there's usually nothing left to ask about.

**Only ask the "anything else?" question IF** during recording the user mentioned doing something outside Claude — e.g., *"I just checked our Slack",* *"I looked at the LinkedIn profile in another tab,"* *"I asked Sarah on the team,"* *"I scrolled the dashboard in my browser."*

In that case, ask:

> *"Quick — anything from outside Claude (Slack, browser tabs, decisions in your head) that should be part of the skill?"*

If they reply with prose → call **`record_demo_freetext`** with `{demoId, text}`.

If they didn't mention any out-of-Claude activity, **skip this step entirely** and go straight to 3c. Don't pre-ask — it adds friction with no upside since the hooks already covered the workflow.

### Step 3c — Generate the interview questions

Call **`interview_for_skill`** with:
- `demoId`: from Phase 1
- `step: "generate"`

You'll get back 3-8 structured questions, each typed (decision / output / signal / edge_case / general). Read them yourself first.

### Step 3d — Ask the user the questions ONE AT A TIME (use AskUserQuestion with the supplied options)

Every question from Step 3c ships with a `question.options` array of 3-4 plausible answers the user can pick from. Use the **`AskUserQuestion`** tool to render them — that way the user clicks instead of typing, and the experience is consistent across every captured skill.

For each question, call **`AskUserQuestion`** with:
- `question`: the question's `question` field verbatim
- `header`: a short chip label derived from `questionType` (e.g. "Output", "Edge case", "Signal", "Decision", "Context")
- `multiSelect`: `false` (default — only `true` if the question explicitly asks for multiple selections)
- `options`: map each item in `question.options` to `{ label: <option.label>, description: <option.description> }`. **Append " (Recommended)" to the FIRST option's label** — that's the Haiku-suggested default based on the trace.

Do NOT add an "Other" option yourself — `AskUserQuestion` always lets the user provide custom free-text input, so the escape hatch is automatic.

**Ask one question at a time.** Wait for the answer, then call **`interview_for_skill`** with:
- `demoId`
- `step: "answer"`
- `question`: the verbatim question text
- `answer`: the option label the user picked, or their free-text response if they chose Other

Then proceed to the next question.

If the user gets impatient ("just do it", "enough", "save it"), STOP and move to finalize — better to ship with partial answers than annoy the user out of the flow.

### Step 3e — Finalize the skill

When all questions are answered (or the user says "enough", "just save it", etc.), call **`interview_for_skill`** with:
- `demoId`
- `step: "finalize"`
- `finalName`: confirmed skill name (refine from the proposedName if the user wants — ask before changing)
- `finalIntent`: optionally refined intent (defaults to the initialIntent)
- `scope`: "org" (default) or "private" (only ask if the user implies it should be just theirs)
- `activate`: true if the user already said "yes activate it for everyone"; otherwise leave false (saves as draft)
- **`replacingSkillId`** — REQUIRED if Phase 0 routed this as an "update existing" path. Pass the skillId you captured in Phase 0. This tells the backend to REPLACE the existing skill's content with the new demonstration (vs creating a new skill). The skill's version bumps, history records the change, and (if originally a draft) it auto-activates. Forks promote out of fork-state on first edit (counts as 1 capture against quota).

  If `replacingSkillId` is set, the response will include `replacedTarget: {id, slug, name}` and `wasFirstEditToFork: boolean`. Use the latter to mention "this counted as 1 capture against your monthly quota" if it was a fork-first-edit.

  DO NOT pass `replacingSkillId` if Phase 0 confirmed this is a new skill — that would replace the wrong skill.

### Step 3f — Confirm + show preview

Show the user:
- The skill name + slug
- Status (draft or active)
- The structureCompleteness score (0-4 — how many of {inputs, outputContract, decisionPoints, outcomeSignal} are populated)
- A preview of the generated SKILL.md (first 800 chars from `contentPreview`)
- The PII scrub stats if any redactions happened

If status is 'draft', ask: *"Activate this org-wide so anyone can use it? Reply yes / not yet / let me edit first."*

### Step 3f.5 — Offer to schedule it

The finalize response includes a **`recommendedCadences`** field — 4 ranked cadences inferred from the skill's intent + tools + content, plus a "skip" hint. Render this as a numbered list and let the user pick one. This is where most users will decide whether the skill becomes a daily habit or stays ad-hoc.

Use **`AskUserQuestion`** with:
- `question`: *"want to run this on a schedule? i can wire it up now."*
- `header`: `"Schedule"`
- `multiSelect`: `false`
- `options`: 4 entries from `recommendedCadences.options` (label = `option.label`; append `" (Recommended)"` to the FIRST option only) PLUS a final option `{ label: "Skip - ad-hoc only", description: "you can schedule it anytime with /implexa:schedule" }`. The user can also type a custom schedule like "every 4 hours" or "daily at 6pm" via the Other free-text input.

Map the reply:

**If the user picks one of the 4 cadences (or types a custom schedule):**

1. Call **`schedule_skill`** with:
   ```jsonc
   {
     "skillSlug":   "<slug from finalize>",
     "scheduleNl":  "<their pick — e.g. 'daily at 8:55am' — or their free-text>",
     "destination": { "type": "dashboard" }
   }
   ```

2. On `ok: true`, call **`mcp__scheduled-tasks__create_scheduled_task`** with:
   - `prompt`: the returned `claudeScheduledTaskPrompt` (e.g. `/implexa:run-scheduled <uuid>`)
   - `cron`: the returned `cronExpression`
   - `timezone`: the returned `timezone`

3. Confirm to the user, ≤ 2 lines:

   ```
   scheduled. runs <humanizedSchedule>. output lands at app.implexa.ai/runs.
   manage at app.implexa.ai/scheduled.
   ```

**If the user picks "Skip - ad-hoc only" (or replies "skip" / "not now" / "later"):**

Tell them: *"saved. you can schedule it anytime with `/implexa:schedule <slug>`."* Move to Step 3g.

**Notes**:
- Default destination is `{ type: "dashboard" }`. Do NOT ask about Slack here. The user can layer Slack on later via `/implexa:schedule`.
- If `schedule_skill` fails (bad parse, unknown skill, etc.), surface the error and offer to retry with a different cadence. Don't block the rest of the post-save flow.
- If `mcp__scheduled-tasks__create_scheduled_task` is unavailable, the Implexa manifest is still saved — tell the user they can run `/implexa:run-scheduled <id>` manually.

### Step 3g — Offer to share

After the skill is saved (and activated, if the user chose to), ALWAYS offer to share it. This is the viral primitive — every captured skill is one share away from spreading. Ask one clean question:

> *"Want to share this with your team or post publicly? I can generate a link in 5 seconds — team links are gated to your email domain, public links work anywhere (Slack, LinkedIn, X)."*

Map the reply:
- *"team"* / *"my team"* / *"colleagues"* / *"internal"* → call `create_share_link({skillSlug, shareMode: "team"})`
- *"public"* / *"Slack"* / *"LinkedIn"* / *"Twitter"* / *"X"* / *"anywhere"* → call `create_share_link({skillSlug, shareMode: "public"})`
- *"not now"* / *"skip"* / *"later"* → don't call. Move on.
- *"both"* → create one of each, render both URLs.

When the call returns, render the URL prominently (full URL, with the gate description) and offer one suggested distribution channel matching the mode. Defer to `/implexa:share-this` for any follow-up share questions.

## What's next?

- `Share this skill with my team`
- `Share this skill publicly`
- `Show me other skills my org has saved`
- `Use this skill on another company`

## Notes for the model

- **The interview is the magic.** Skip it and you produce a flat prompt. Walk through it and you produce a structured skill. Always do the interview unless the user explicitly says "skip it".
- **The schedule prompt is bundled.** Step 3f.5 is mandatory whenever finalize returns a `recommendedCadences` field. Don't skip it. Most users don't know `/implexa:schedule` exists; surfacing the 4 cadences at the moment of save is what converts "saved a skill" → "saved a habit".
- **Three capture surfaces — use all three.** external-data tool calls (automatic), non-Implexa actions via `record_demo_note` (manual — your job), and host-forwarded transcript (automatic via hooks). If you skip `record_demo_note` after a WebSearch, that step vanishes from the skill.
- **`record_demo_note` is cheap.** One sentence summary, fire-and-forget, silently drops if no demo is running. Call it generously. Better to overlog than to leave a gap in the procedure.
- **The "anything else?" question is required.** After `end_demonstration` and before `interview_for_skill`, always ask the user the free-text question. The user may skip; that's fine. But don't skip *asking*.
- **Decision notes matter.** When you make a routing choice (LinkedIn over Twitter, this CRM filter over that one), say so briefly in your response AND `record_demo_note` it. Those notes get logged as decisions and become conditionals in the final skill.
- **Don't auto-end.** Wait for the user's explicit "done" signal. Mid-workflow they may pause to think — that's not "done", that's just a pause.
- **Single active demo per user.** If the user calls start_demonstration while one's already active, the prior one auto-abandons. Mention it: *"You had a previous recording in progress — I closed it without saving. Starting fresh."*

## Error handling

| Error from a tool                       | Diagnosis                              | Tell the user                                                                                                  |
|-----------------------------------------|----------------------------------------|------------------------------------------------------------------------------------------------------------------|
| `No active recording demonstration`     | end_demonstration called without start | "I don't see an active recording — call start_demonstration first."                                            |
| `step='answer' requires question and answer` | Missing arg in answer call          | Re-call with both fields populated.                                                                              |
| `Skill generation failed: <Anthropic err>` | Haiku API error                       | Tell user: "Skill author hit a temporary error. Want to retry the finalize step?"                                |
| `forbidden — demo belongs to a different org` | Cross-org demoId passed              | Stop. Explain the user can only finalize their own demos.                                                        |
| Demo status mismatch                    | finalize called before interview done  | Tell the user the interview isn't complete and offer to skip remaining questions and finalize anyway.            |
