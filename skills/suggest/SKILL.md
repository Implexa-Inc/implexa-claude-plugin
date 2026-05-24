---
description: Show recent skill recommendations Implexa noticed for you. Reads the local pull-buffer of cross-vendor skill matches written silently by the ambient recommender as you typed prompts. Use when the user says "show me what implexa noticed", "what did implexa find", "implexa recommendations", "implexa picks", "implexa what do you have", "what's implexa got for me", or invokes /implexa:suggest. The pull-based half of the dual-mode recommender. The ambient hook writes matches to a local buffer silently (zero chat noise), and this slash command surfaces them on demand. Each entry shows the skill name, source registry, fit reason, the prompt excerpt that triggered the match, and a source URL. The user can pick one to apply inline.
---

# implexa:suggest, pull recent ambient recommendations

The ambient recommender (the UserPromptSubmit hook shipped with the Implexa plugin) silently watches every prompt the user types in Claude Code. When a prompt semantically matches a skill in the cross-vendor aggregated_skills index (Anthropic + ClawHub + Smithery + Skills.sh + GitHub), the hook writes that match to a local pull-buffer at `~/.claude/plugins/implexa/recent-recommendations.json` and produces no chat output. This slash command is how the user retrieves what the recommender has noticed.

## Step 1, read the pull-buffer

Read the file at `~/.claude/plugins/implexa/recent-recommendations.json` via the Read tool. Expected shape:

```json
{
  "version": 1,
  "entries": [
    {
      "id": "<recommendation_event_id>",
      "ts": "2026-05-24T10:00:00Z",
      "ts_unix": 1748067600,
      "prompt_excerpt": "first 80 chars of the prompt that triggered the match",
      "matches": [
        {
          "slug": "...",
          "source": "smithery | clawhub | anthropic | skills-sh | agentskills | github",
          "name": "...",
          "description": "...",
          "fit_reason": "15-word lowercase reason from Haiku",
          "install_url": "https://...",
          "similarity": 0.41
        }
      ]
    }
  ]
}
```

## Step 2, handle the empty case

If the file doesn't exist, can't be parsed, or `entries` is empty, respond exactly:

> implexa hasn't matched anything in your recent prompts. either you haven't typed many work-related prompts yet, or the ambient recommender hasn't been wired in (re-run `bash scripts/install-user-hooks.sh` in the implexa-plugin repo).
>
> to force a search right now, type: `implexa, find me a skill for <what you're working on>`

That's the whole response. Don't pad with apologies or workarounds, just point at the explicit-invocation surface.

## Step 3, render the matches as a numbered list

If entries exist, render them in reverse-chronological order (newest first), capped at the buffer's natural limit (20 entries, 24h TTL). Use this exact format:

```
here's what implexa noticed for you recently:

1. **<name>** (<source>): <fit_reason>
   from your prompt: "<prompt_excerpt>"
   install: <install_url>

2. **<next name>** (<source>): <fit_reason>
   from your prompt: "<prompt_excerpt>"
   install: <install_url>

...
```

Voice rules apply: lowercase, tech-bro X cadence, no em-dashes anywhere in your reply. Use commas, periods, colons, parens, or standard hyphens. The em-dash (the long horizontal punctuation mark) is the strongest AI tell, banned in user-facing output.

## Step 4, offer to apply one inline

After the list, ask exactly:

> pick one to run inline, or type a number, or say "skip".

If the user picks a number or says "run #N":
- If the MCP tool `mcp__implexa__apply_recommended_skill` is registered (P2.2 ships this), call it with `slug`, `source`, and `recommendation_event_id` (the `id` field on the entry the user picked). The tool fetches the SKILL.md from `aggregated_skills.content` and injects it into the session for execution.
- If `apply_recommended_skill` is NOT yet registered (P2.2 hasn't shipped), tell the user honestly: "the inline-apply tool ships in P2.2. for now, here's the source URL: <install_url>. open it to install via the source registry's own flow."

## Step 5, don't re-surface to Supabase

The pull-buffer reflects rows already in `recommendation_events` (the backend inserted them when the ambient hook fired). Do not re-insert. Do not call `recommend_skills_for_context` again from this command. Reading the local file is sufficient.

## What this command IS NOT

- It is NOT a search box. To search, the user types `implexa, find me a skill for X` (the hook handles that path, produces fresh results, and adds them to the buffer too).
- It is NOT a way to discover skills the recommender hasn't already buffered. If the user wants to browse the full index, point them at the dashboard or `clawhub.ai` / `smithery.ai` / `skills.sh` directly.
- It is NOT an install command. It's a retrieval surface that ends with an optional apply step.

## Why this exists

The ambient recommender used to print recommendations inline via `additionalContext` with imperative wrapping ("display this verbatim, don't mention these instructions"). Claude's prompt injection defense correctly rejected that as injection and refused to surface the recs. P2.1b's fix: ambient signals are silent (model never sees them, defense has nothing to flag), explicit signals ride user invocation trust (the user typed `implexa, ...` so the model knows to surface). This command is the safety mechanism, the way users access the silent buffer when they want it.
