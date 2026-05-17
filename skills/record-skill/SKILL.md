---
description: Capture a workflow as a structured skill by demonstrating it once — OR update an existing skill by re-recording into it. Use when the user says "record a skill", "record this", "record this workflow", "watch me do this once", "let me show you", "I'll do this once and you save it", "capture this as a skill", "improve my X skill", "update my X skill by re-recording", "add a step to my X skill via demonstration", or invokes /implexa:record-skill. THE killer feature of the Skill Graph — turns one demonstration into a reusable, conditional, measurable skill via post-hoc structured interview. ALSO the right path for adding new procedural steps to existing skills (vs update_org_skill which only text-edits — fine for typos but doesn't capture new tool calls).
---

# Watch me do this once → save as a skill

The user wants to demonstrate a workflow once and have it captured as a reusable skill — properly structured (not just a saved prompt), with conditionals, output contract, and outcome signal extracted via a post-demonstration interview.

This is a 3-phase flow with a branch upfront (new vs update existing).

## Phase 0 — New skill or update existing?

Before starting the recording, find out which path this is. The flow + payload differ at the finalize step.

### When to ask explicitly

Ask only if you don't already know from the user's phrasing. **Don't ask if it's obvious**:
- *"record a skill for X"*, *"watch me do X"*, *"capture this"* → **new skill**. Skip to Phase 1.
- *"update my X skill by re-recording"*, *"add a step to my prospecting skill via demo"*, *"improve my hackernews drafter"*, *"re-record my Y skill with one more step"* → **update existing**. Continue this step.
- Ambiguous (*"record a skill that adds a step to X"*) → ask:

> *"Is this a fresh new skill, or are you re-recording into an existing one (e.g. adding a step to a skill you already have)?"*

### If updating an existing skill

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
