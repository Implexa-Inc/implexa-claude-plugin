---
description: Update an existing skill by re-recording — add a step, refine a branch, or extend the behavior. Use when the user says "update my X skill", "improve my X skill", "add a step to my X skill", "re-record my X skill", "refine my X skill", "modify my Y workflow", "extend my Z skill", or invokes /implexa:update-skill. This is the RE-RECORD path — the user demonstrates the new behavior live and the existing skill's content gets MERGED with the new demonstration (existing steps preserved, new step integrated, error handling appended). For text-only changes (typos, renames, copy polish), use update_org_skill instead.
---

# Update an existing skill (re-record + merge)

The user wants to add a step, refine a branch, or extend an existing skill. **This is the re-record path** — they demonstrate the new behavior live, and the existing SKILL.md gets MERGED with the new demonstration (not replaced). Existing procedure preserved, new step woven in, error handling appended.

Why re-record vs. text-edit (update_org_skill)?
- **Re-record** captures REAL tool calls, REAL decision points from a live demonstration. The new step is grounded in observed behavior.
- **Text-edit** just rewrites the SKILL.md from a description. Claude imagines what the new step should do — risky for behavior, fine for typos.

Use this skill for behavioral changes. Use update_org_skill for copy changes.

## Phase 1 — Identify the target skill

If the user named the skill (*"improve my HN drafter"*), find it. Call `list_org_skills` with:
- `query`: the user's substantive words (e.g. "HN drafter", "prospecting", "investor outreach")
- `createdByMe`: **true** (their own skills first — almost always what they meant by "my skill")

### Interpret the results

- **Exactly 1 hit** → confirm with the user: *"Improving `<skill name>` (v<X>). Ready to start the demonstration?"* → Phase 2.
- **Multiple hits** → render as a numbered list with version + last-used:

  ```
  Found these skills matching "<query>":
    1. 🔒 HackerNews comment drafter (v3) — last used 2d ago
    2. 🌍 HN trending Claude posts (v5) — last used 6h ago

  Which one are you improving? Reply with a number.
  ```

- **0 hits in their library** → expand the search. Call `list_org_skills` again WITHOUT `createdByMe` (full org). If still 0, with `includeUniversal: true` (public library). If they pick a public skill, route through `/implexa:fork` first (you can't directly improve someone else's universal skill — you need a copy in your org first).
- **0 hits anywhere** → *"No skill matches '<query>'. Want to capture this as a NEW skill instead? Run `/implexa:record-skill`."*

### Once the user has confirmed the target skill, capture its `skillId`. You'll pass this as `replacingSkillId` at finalize.

## Phase 2 — Confirm the update intent + start the recording

Ask the user **what they're about to demonstrate** (the addition / change). One sentence. Examples:
- *"Adding a step to summarize each thread before drafting"*
- *"Adding X (Twitter) support alongside HN"*
- *"Refining the depth-match heuristic to skip vapid threads"*

Then call **`start_demonstration`** with:
- `initialIntent`: the user's one-sentence answer (framed as the UPDATE goal — what's being added/changed, NOT the original skill's purpose)
- `proposedName`: leave OUT — the existing skill name will be preserved at finalize
- `sessionId`: the current session id

Confirm to the user:

> *"Recording. Demonstrate the new behavior — I'll capture every tool call. When you finish, the existing skill's procedure will be PRESERVED and the new demonstration will be merged into it (added as a new step, refined in place, or appended to error handling — whichever fits). Tell me when you're done."*

## Phase 3 — Let the user demonstrate

Same as `/implexa:record-skill`'s Phase 2 — execute their requests, call `record_demo_note` for non-Implexa actions (WebSearch, Bash, browser MCP, manual reasoning steps), don't lead.

When the user signals they're done (*"ok done"*, *"that's it"*, *"save it"*), move to Phase 4.

## Phase 4 — End, interview, finalize with merge

### Step 4a — End the recording

Call **`end_demonstration`** with the demoId.

### Step 4b — (Conditional) free-text capture

Same rule as `/implexa:record-skill` — only ask "anything else?" if the user mentioned out-of-Claude work during the demo. Otherwise skip.

### Step 4c — Generate interview questions

Call **`interview_for_skill`** with:
- `demoId`
- `step: "generate"`

You'll get back 2-4 questions, each shipping with 3-4 `options` items.

### Step 4d — Ask the questions ONE AT A TIME via AskUserQuestion

For each question, use the **`AskUserQuestion`** tool with:
- `question`: the question's `question` field verbatim
- `header`: short chip label from `questionType` ("Output", "Edge case", "Signal", "Decision")
- `multiSelect`: `false` (unless the question explicitly asks for multiple selections)
- `options`: map each `question.options` item to `{ label, description }`. Append " (Recommended)" to the FIRST option's label.

Don't add "Other" yourself — AskUserQuestion provides a free-text fallback automatically.

After each answer, call **`interview_for_skill`** with:
- `demoId`
- `step: "answer"`
- `question`: the verbatim question text
- `answer`: the option label the user picked, or their free-text response

If the user says "just save it" / "enough", STOP and finalize with partial answers.

### Step 4e — Finalize with merge (THIS IS THE CRITICAL PART)

Call **`interview_for_skill`** with:
- `demoId`
- `step: "finalize"`
- **`replacingSkillId`**: the skillId captured in Phase 1 — REQUIRED on this path
- `finalName`: leave OUT (preserve the existing skill name) UNLESS the user explicitly wants a rename
- `finalIntent`: leave OUT (preserve the existing intent) UNLESS the user explicitly wants to reframe
- `scope`: leave OUT (preserve existing scope)
- `activate`: leave OUT (the existing skill is already active; promotion handled by editSkill)

The backend will:
1. Fetch the existing skill's SKILL.md
2. Pass it to the Haiku author as `existingContent` (MERGE MODE)
3. Haiku produces a merged SKILL.md — existing steps preserved, new demo integrated
4. The target skill version bumps, history records the change

### Step 4f — Show what changed

Display:
- Old version → new version (e.g., "v3 → v4")
- The new step(s) added (briefly summarize from the diff)
- Any error-handling rows newly appended
- The structureCompleteness score
- A preview of the merged content (first 1500 chars)

Mention `wasFirstEditToFork: true` if applicable: *"This counted as 1 capture against this month's quota since it was a fresh fork's first edit."*

## Phase 5 — Offer to share (optional)

If the existing skill was already shared (team or public), no need to ask — the merge keeps the share active.

If it wasn't shared, ask once:

> *"This update is now in v<X>. Want to share the improved version with your team or publicly? Or is it just for you?"*

Map the reply to `create_share_link({skillSlug, shareMode})` as usual.

## What's next?

- `Test the updated skill — run it now`
- `Roll back to the previous version` (use `update_org_skill` with the prior content from history)
- `Capture a different workflow as a new skill — /implexa:record-skill`

## Notes for the model

- **This is the BEHAVIORAL update path.** Use `/implexa:update-skill` for: adding a step, refining tool calls, adding a branch, changing an output format that involves new tool calls. Use `update_org_skill` for: typos, renames, copy polish.
- **`replacingSkillId` is REQUIRED at finalize.** Without it, the new demonstration creates a SEPARATE new skill instead of updating the target. Double-check before calling finalize.
- **Don't pass `finalName` / `finalIntent` / `scope` / `activate` at finalize** unless the user explicitly asked to change those. The merge preserves them by default.
- **Don't ask about scope or sharing during the flow** — the existing skill already has its scope decided. The merge maintains it.
- **The demonstration should focus on the NEW behavior**, not re-running the entire skill. The user's mental model is "add this step" — let them demo ONLY that step. The merge will integrate it correctly.
- **If the user accidentally demonstrated the WHOLE workflow (existing + new)** — that's fine, merge still works (Haiku is told to preserve existing structure unless the new demo contradicts it).
- **If the user tries to /implexa:update-skill a SYSTEM Playbook or another org's universal skill** — block. Tell them: *"That's not in your org. Fork it first via `/implexa:fork`, then improve your copy."*

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `list_org_skills` returns 0 in their library, org, AND universal | Skill doesn't exist anywhere | "No skill matches '<query>'. Want to capture this as a NEW skill instead? Run `/implexa:record-skill`." |
| User tries to improve a `scope=system` skill | System Playbooks are immutable | "System Playbooks can't be directly improved. Fork it via `/implexa:fork`, then `/implexa:update-skill` your copy." |
| `interview_for_skill` step='finalize' returns `quota_exceeded` | First edit to a fork on Free plan counts toward 5/month cap | "This is your first edit to a fork, which counts as 1 capture. You've hit your monthly cap. Upgrade at https://app.implexa.ai/pricing or wait for the 1st of the month." |
| `interview_for_skill` returns `replacingSkill not found or no permission` | Bad skillId or skill belongs to a different org | "I can't update that skill — it's not in your org or doesn't exist. Check `/implexa:my-skills` to see what you have." |
| Demo ends with 0 tool calls + 0 conversation turns | Recording didn't capture anything | "I didn't see any tool calls during the recording. The merge would have nothing to integrate. Want to try again, or cancel?" |
