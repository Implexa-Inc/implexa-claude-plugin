---
description: 'Edit an existing Implexa agent from a plain-English change, then have it take effect for any schedule automatically. Use when the user says "update this agent to also do X", "edit the <name> agent", "add a step to my agent", "change the SEO agent to look at Google Search Console", "make the agent also edit existing pages", "remove the X step", or otherwise wants to change an agent''s steps. THE natural-language agent-edit path: resolves the target agent, composes the full revised step chain, and calls revise_workflow, which binds the new steps (verify gate + outcome prior) and either revises the user''s own agent in place or forks a shared/curated agent into their copy and re-points their schedules at it. The next scheduled run uses the change with no re-scheduling and no prompt edit.'
---

# Edit an agent (natural language)

The user wants to change an agent's steps in plain English. Turn that into a clean revision that takes effect everywhere, including any schedule that uses it.

## Step 1: Resolve the target agent

Identify which agent the user means.

- If they reference one by name/slug ("the SEO agent", "seo-content-brief-drafter"), call **`get_workflow`** with `{ slug, source }` (source defaults to `web-seed`; for an agent they generated, use `generated`). If unsure which, call **`list_workflows`** and match by name.
- If they say "this agent" mid-conversation, use the one most recently discussed (its `workflow_id` from a prior `get_workflow` / `apply_workflow`).

You need the agent's **`id`** and its **current `steps`** (from `get_workflow`).

## Step 2: Compose the FULL revised step chain

Build the **complete** new step list, not a diff: take the current steps and apply the user's change (add / replace / reorder / remove). Each step is `{ order, intent, kind, integration?, fallbacks? }`:

- `intent`: a verb-led, concrete action ("pull google search console performance: top queries and pages by impressions, CTR, position").
- `kind`: `skill` (bind to a verified agent component), `tool` (an integration / Chrome-MCP / API action, carry `fallbacks`), or `decision` (pure logic / approval gate).
- For a tool step that has a specific integration, set `integration` ({source,slug} or a query string); otherwise leave it for the model / Chrome MCP and give `fallbacks` (a manual path).

Keep the user's intent faithful. Anything touching a real client should still end at a `decision` approval gate.

## Step 3: Apply the revision

Call **`revise_workflow`** with `{ workflow_id, steps, summary }` where `summary` is one line describing the change (e.g. "added a Search Console pull + an edit-existing-page action").

The tool:
- **Binds** the new/changed steps to verified agent components (the same verify gate + outcome prior as generation), so new steps are real, not unbound.
- If this is the user's own generated agent → **revises it in place** (a new changelog version).
- If it is a shared/curated (`web-seed`) agent → **forks it into the user's own editable copy** (so the edit is theirs and survives re-seeds) and **re-points the user's schedules** that targeted the original at the fork.

## Step 4: Report (one short paragraph)

Tell the user, in plain language:
- what changed (the steps added/replaced),
- whether it was revised in place or **forked into their own copy** (mention the new slug),
- how many of their **schedules were re-pointed** (if any), and
- that **the next scheduled run will use the updated agent automatically**: no re-scheduling, no prompt edit.

Then surface the workflow URL (`url` from the tool) so they can see it.

## Notes

- **Bound coverage may be < 100%.** If `revise_workflow` reports unbound steps (no agent component matched the intent), say so plainly: those steps run with the model filling them. That is honest, not a failure.
- **Do not edit an agent the user did not ask to change.** One request = one revision.
- **This is the "just say it" path.** Because schedules point at the agent by id and the fork re-points them, the user never has to touch a routine prompt to change what a scheduled agent does.
