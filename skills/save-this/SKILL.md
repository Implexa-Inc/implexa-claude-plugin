---
description: Save the current Claude workflow as a reusable, org-shared skill. Use when the user says "save this", "save this as a skill", "make this a skill", "remember this for next time", "let everyone in the org do this", "turn this into a workflow", "save the playbook", or "create a skill from what we just did". Captures the session's tool calls + the user's stated intent, generates a SKILL.md via Haiku, scrubs PII, stores it scoped to the user's org. From that moment, any user in the org can invoke it via /implexa:org-skills or natural language. Powers the Skill Graph — Implexa's substrate-level execute → map → track → repeat loop.
---

# Save this workflow as an org skill

The user just did some work and wants to save it so their team can re-run it. Run this end-to-end. Do NOT improvise — every step matters because the captured artifact will be re-used by other people without context.

## Step 1 — Confirm the user's INTENT in one sentence

This is the most important step. The captured trace tells us WHAT was done; only the user can tell us WHY. Without the why, the skill has no purpose anchor and won't generalize.

Ask exactly: **"In one sentence, what were you trying to accomplish?"**

Examples of good intent:
- *"Warm up an enterprise customer who's up for renewal in 90 days."*
- *"Find candidates for a Bullhorn job order that came in this morning."*
- *"Build a competitive landscape brief for a target company before a sales meeting."*

If the user gives you a vague answer ("doing some research"), push back ONCE: *"Can you say it more specifically — what's the goal?"*

## Step 2 — Propose a slug-friendly skill name

Take the intent and propose a name. Aim for 2-5 words, action-flavored:
- "Warm up enterprise renewal"
- "Fill this Bullhorn role"
- "Build competitive brief"

Confirm the name with the user. Suggest 2-3 alternatives if they don't like the first.

## Step 3 — Summarize the workflow yourself before calling the tool

Before calling `capture_workflow_as_skill`, build these inputs from your own memory of the session:

- `name`: what the user just confirmed
- `intent`: what the user just said (Step 1)
- `toolsUsed`: distinct MCP tool names you called this session (deduplicate)
- `traceShape`: ordered tool-name sequence in the order you called them
- `traceSummary`: ONE PARAGRAPH narrative — what you did, in what order, and why each step. This is what Haiku uses most when authoring the SKILL.md.
- `exampleArgs`: 2-4 specific arg values that illustrate the workflow shape (will be PII-scrubbed)

Be honest in `traceSummary`. If you tried something that didn't work and pivoted, include it — the skill author may render it as a fallback step. If you don't include it, the generated skill misses important nuance.

## Step 4 — Call capture_workflow_as_skill

Call **`capture_workflow_as_skill`** with the inputs from Step 3. Default: `scope: "org"` and `activate: false` (creates as draft).

Display the generated SKILL.md preview to the user. The result will include `contentPreview` (first 800 chars) — show that.

## Step 5 — Confirm activation

Ask: **"Activate this for everyone in your org? Reply yes to make it discoverable, or 'edit' to refine first."**

- On **yes** → call `capture_workflow_as_skill` again with `activate: true` only if you didn't pass it the first time, OR run a follow-up to flip status. (V1: just tell the user the skill is now live and discoverable via `/implexa:org-skills`.)
- On **edit** → ask what they'd like to change, then re-call `capture_workflow_as_skill` with refined inputs. Don't try to edit the SKILL.md yourself — re-author it.
- On **no / not yet** → leave as draft. Tell them they can find it in `/implexa:org-skills` later.

## What's next?

- `Show me what other skills my org has saved`
- `Let everyone use this skill — activate it`
- `Show skill ROI — which of our skills are driving outcomes`

## Notes for the model

- **Don't write the SKILL.md yourself.** The `capture_workflow_as_skill` tool calls Haiku to author it. If you write it yourself you'll drift from the org's authored format and you'll skip PII scrubbing.
- **PII is auto-scrubbed.** The `scrubReplacements` field in the response shows what was redacted. If lots of redactions happened, mention it: *"I scrubbed N email addresses and M dollar amounts before saving."*
- **Don't pad the trace.** If the user only ran 2 tool calls, save 2-tool skills. Forcing 5 steps when 2 happened produces a worse skill.
- **One workflow per skill.** If the user did three unrelated workflows, ask which one they want to save and offer to save the others separately.
- **Generic intent → vertical-agnostic skill.** This skill is the platform layer — it doesn't matter if the workflow was sales, recruiting, or competitive research. The substrate is horizontal.

## Error handling

| Error from the tool                       | Diagnosis                              | Tell the user                                                                                                              |
|-------------------------------------------|----------------------------------------|----------------------------------------------------------------------------------------------------------------------------|
| `intent is required`                      | Skipped Step 1                         | Loop back to Step 1 and ask for intent in one sentence.                                                                    |
| `Skill generation failed: <Anthropic err>`| Haiku call hit an API error            | Tell the user: "Skill generation hit a temporary error. Want to try again, or save just the trace as a draft?"             |
| `Skill generation returned malformed content` | Haiku didn't produce valid frontmatter | Retry once. If still fails, tell the user it failed and suggest they describe the intent more specifically.                |
| `slug collision` (handled silently)       | Org already has a skill with this slug | The tool auto-appends a numeric suffix (`-2`). No user-visible error.                                                      |
