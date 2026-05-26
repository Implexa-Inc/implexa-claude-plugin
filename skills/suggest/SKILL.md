---
description: 'Suggest skills for what the user is working on. Two modes: (1) ACTIVE SEARCH if the user supplied a query ("suggest skills for social media", "find me something for cold email"), runs a fresh cross-vendor search AND merges in their buffered matches. (2) PASSIVE PULL if no query, just shows the recent recommendation buffer (what implexa noticed silently). Trigger phrases: "show me what implexa noticed", "what did implexa find", "implexa recommendations", "implexa picks", "implexa what do you have", "what''s implexa got for me", "suggest a skill for X", "is there a skill for X", or invokes $implexa-suggest with or without args. Each entry shows the skill name, source registry, fit reason, prompt excerpt, and source URL. The user can pick one to apply inline.'
---

# implexa:suggest, pull + search recommendations

Dual-mode skill recommender:

- **active search**: if the user provided a query (open-ended question like "suggest a skill for social media" or "is there a strong skill for X"), do a fresh cross-vendor recommender call AND merge in any buffered matches the user might already have. This is the common case from the slash-command menu.
- **passive pull**: if the user invoked /implexa:suggest with NO args (just wants to see what implexa has been silently noticing), skip the fresh search and only show the buffer. Common case from the ambient recommender's UserPromptSubmit hook in Claude Code.

The buffer lives server-side as of 2026-05-27 (not a local file), so this skill works the same across Claude Code, Codex, and any other MCP-compatible host.

## Step 0, detect mode

Look at the user's invocation:
- If they typed any natural-language query along with the command (e.g. `$implexa-suggest something to improve my social media`, or "suggest skills for cold email"), set `mode = "active"` and capture the query.
- If they invoked it bare (`$implexa-suggest` or `/implexa:suggest` with no follow-on text), set `mode = "passive"`.

When in doubt, default to `active` if there's ANY user-provided text beyond the slash command itself. Better to do a fresh search than to surface a stale buffer.

## Step 1a, ACTIVE mode: run a fresh search

Call `mcp__implexa__recommend_skills_for_context` with:

```json
{
  "messages": ["<the user's query verbatim>"],
  "topN": 10,
  "skipGates": true,
  "source": "explicit"
}
```

`skipGates: true` returns raw top-N by similarity (no gap filter), which is what you want for explicit searches. `source: "explicit"` tags the call in the server-side buffer so future passive pulls know it was user-initiated.

The response shape:
```json
{
  "matches": [
    { "skill_id", "source", "name", "slug", "description", "score", "fit_reason", "install_hint" }
  ],
  "recommendation_event_id": "<uuid>"
}
```

If `matches` is empty, fall through to Step 1b (the buffer might have something tangentially relevant).

## Step 1b, fetch the recent buffer (BOTH modes)

Call `mcp__implexa__list_recent_recommendations` with these args (all optional, defaults shown):

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

## Step 2, merge active + buffer results

You now have up to two result sets:
- `active_matches` from Step 1a (only if mode='active')
- `buffer_entries` from Step 1b (always)

Build the unified list:

1. If `mode='active'` AND `active_matches` is non-empty:
   - Render active matches FIRST (they're targeted to the query).
   - Then any buffer entries that are RELEVANT to the same query, deduped by (source, slug). Skip irrelevant buffer noise.
2. If `mode='active'` AND `active_matches` is empty:
   - Render buffer entries that match the user's query topic. If none, say so honestly and suggest they rephrase.
3. If `mode='passive'` AND buffer is non-empty:
   - Render buffer entries only (no fresh search needed).
4. If both modes return nothing usable, respond:

   > implexa didn't find anything strong for that. either rephrase (more specific verbs/tools/outcomes), or check the full index at https://implexa.ai/search

   No padding, no apologies.

## Step 3, render the unified list

Use this format:

```
here's what implexa found for "<query if active, else 'you' if passive>":

1. **<name>** (<source>): <fit_reason>
   score: <score if present, else "buffered">
   install: <install_hint>

2. **<next>** (<source>): <fit_reason>
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
