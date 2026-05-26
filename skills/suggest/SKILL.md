---
description: Show recent skill recommendations Implexa noticed for you. Reads the server-side recommendation buffer populated by the ambient hook (Claude Code) and by every explicit implexa search (works on any runtime). Use when the user says "show me what implexa noticed", "what did implexa find", "implexa recommendations", "implexa picks", "implexa what do you have", "what's implexa got for me", or invokes /implexa:suggest. The pull-based half of the dual-mode recommender. Each entry shows the skill name, source registry, fit reason, the prompt excerpt that triggered the match, and a source URL. The user can pick one to apply inline.
---

# implexa:suggest, pull recent recommendations

The ambient recommender (the UserPromptSubmit hook shipped with the Claude Code plugin) silently watches every prompt you type and matches it against the cross-vendor aggregated_skills index (Anthropic + ClawHub + Smithery + Skills.sh + GitHub). Explicit implexa: searches (`implexa, find me a skill for X`) also feed the same buffer. This command surfaces what's there.

The buffer lives **server-side** as of 2026-05-27 — it's not a local file. That makes /suggest work the same in Codex and any other MCP-compatible host without needing a runtime-specific hook.

## Step 1, fetch the recent matches

Call the MCP tool `mcp__implexa__list_recent_recommendations` with these args (all optional, defaults shown):

```json
{
  "limit":           20,
  "maxAgeHours":     24,
  "dedupePerSkill":  true
}
```

The tool returns `{ ok, count, entries }` where each entry has:

```json
{
  "recommendation_event_id": "<uuid>",
  "source":         "ambient | explicit | periodic",
  "created_at":     "2026-05-27T10:00:00Z",
  "prompt_excerpt": "first 80 chars of the prompt that triggered the match",
  "skill": {
    "skill_id":     "<uuid>",
    "source":       "smithery | clawhub | anthropic | skills-sh | agentskills | github",
    "name":         "...",
    "slug":         "...",
    "description":  "...",
    "fit_reason":   "15-word lowercase reason from Haiku",
    "install_hint": "https://...",
    "score":        0.41
  }
}
```

## Step 2, handle the empty case

If `count` is 0 or the call returns `ok: false`, respond exactly:

> implexa hasn't matched anything in your recent prompts. either you haven't typed many work-related prompts yet, or the ambient recommender hasn't been wired in (re-run `bash scripts/install-user-hooks.sh` in the implexa-plugin repo).
>
> to force a search right now, type: `implexa, find me a skill for <what you're working on>`

That's the whole response. Don't pad with apologies or workarounds.

## Step 3, render the matches as a numbered list

Render in the order returned (newest first), capped at `limit`. Use this exact format:

```
here's what implexa noticed for you recently:

1. **<skill.name>** (<skill.source>): <skill.fit_reason>
   from your prompt: "<prompt_excerpt>"
   install: <skill.install_hint>

2. **<next name>** (<source>): <fit_reason>
   from your prompt: "<prompt_excerpt>"
   install: <install_hint>

...
```

Voice rules apply: lowercase, tech-bro X cadence, no em-dashes anywhere in your reply. Use commas, periods, colons, parens, or standard hyphens. The em-dash (the long horizontal punctuation mark) is the strongest AI tell, banned in user-facing output.

## Step 4, offer to apply one inline

After the list, ask exactly:

> pick one to run inline, or type a number, or say "skip".

If the user picks a number, says "run #N", or any clear affirmative naming one entry ("yes", "go ahead", "apply", "run draft-outreach"):

1. Call the MCP tool `mcp__implexa__apply_recommended_skill` with `slug`, `source`, and `recommendation_event_id` (from the entry the user picked).
2. The tool returns `{ ok, skill_content, skill_metadata, execution_instruction, applied_skill_event_id }`. The full SKILL.md body is in `skill_content`.
3. Execute `skill_content` IMMEDIATELY against the user's current work. Do not summarize the skill, do not paste the SKILL.md back to the user, do not re-ask what they want done. The skill defines its own 6 components (intent, inputs, procedure, decision points, output contract, outcome signal); follow them in order. If the skill needs specific inputs you don't have, ask for just those inputs.
4. If the tool returns `ok: false` (skill removed from the index, content empty, etc.), surface the `error` field honestly and offer the buffer entry's `install_hint` as a fallback.

If the user says "skip" or picks no entry, do nothing.

## What this command IS NOT

- It is NOT a search box. To search, the user types `implexa, find me a skill for X` (which calls `recommend_skills_for_context` directly; that call ALSO gets logged to the server buffer with `source='explicit'` so it shows up here later).
- It is NOT a way to discover skills the recommender hasn't already buffered. If the user wants to browse the full index, point them at the dashboard or `clawhub.ai` / `smithery.ai` / `skills.sh` directly.
- It is NOT an install command. It's a retrieval surface that ends with an optional apply step.

## Migration note (2026-05-27)

Prior versions of this skill read from a local file at
`~/.claude/plugins/implexa/recent-recommendations.json`. That file is no
longer the source of truth — the server-side `recommendation_events`
table is. The Claude Code hook may keep writing the local file as a
warm cache, but this command should always go through the MCP tool so
behavior is identical across runtimes.
