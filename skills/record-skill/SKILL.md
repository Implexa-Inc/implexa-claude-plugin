---
description: Capture a workflow as a structured skill by demonstrating it once. Use when the user says "record a skill", "record this", "record this workflow", "watch me do this once", "let me show you", "I'll do this once and you save it", "capture this as a skill while I do it", "I'm going to walk through this — turn it into a skill", or invokes /implexa:record-skill. Three-phase flow: start_demonstration (open recording) → user does work → end_demonstration → record_demo_freetext (optional "anything else?") → interview_for_skill (Haiku asks 3-8 questions) → finalize → 6-component skill saved org-wide. THE killer feature of the Skill Graph — turns one demonstration into a reusable, conditional, measurable skill via post-hoc structured interview.
---

# Watch me do this once → save as a skill

The user wants to demonstrate a workflow once and have it captured as a reusable skill — properly structured (not just a saved prompt), with conditionals, output contract, and outcome signal extracted via a post-demonstration interview.

This is a 3-phase flow. Don't skip phases.

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

### Step 3d — Ask the user the questions ONE AT A TIME

Don't dump all 8 at once. Ask one. Wait. After each answer, call **`interview_for_skill`** with:
- `demoId`
- `step: "answer"`
- `question`: the verbatim question text
- `answer`: the user's reply

This records the answer in the demo session.

If the user gets impatient ("just do it"), STOP and move to finalize — better to ship with partial answers than annoy the user out of the flow.

### Step 3e — Finalize the skill

When all questions are answered (or the user says "enough", "just save it", etc.), call **`interview_for_skill`** with:
- `demoId`
- `step: "finalize"`
- `finalName`: confirmed skill name (refine from the proposedName if the user wants — ask before changing)
- `finalIntent`: optionally refined intent (defaults to the initialIntent)
- `scope`: "org" (default) or "private" (only ask if the user implies it should be just theirs)
- `activate`: true if the user already said "yes activate it for everyone"; otherwise leave false (saves as draft)

### Step 3f — Confirm + show preview

Show the user:
- The skill name + slug
- Status (draft or active)
- The structureCompleteness score (0-4 — how many of {inputs, outputContract, decisionPoints, outcomeSignal} are populated)
- A preview of the generated SKILL.md (first 800 chars from `contentPreview`)
- The PII scrub stats if any redactions happened

If status is 'draft', ask: *"Activate this org-wide so anyone can use it? Reply yes / not yet / let me edit first."*

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
