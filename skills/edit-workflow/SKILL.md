---
description: 'Edit an existing Implexa workflow from a plain-English change, then have it take effect for any schedule automatically. Use when the user says "update this workflow to also do X", "edit the <name> workflow", "add a step to my workflow", "change the SEO workflow to look at Google Search Console", "make the workflow also edit existing pages", "remove the X step", or otherwise wants to change a workflow''s steps. THE natural-language workflow-edit path: resolves the target workflow, composes the full revised step chain, and calls revise_workflow, which binds the new steps (verify gate + outcome prior) and either revises the user''s own workflow in place or forks a shared/curated workflow into their copy and re-points their schedules at it. The next scheduled run uses the change with no re-scheduling and no prompt edit.'
---

# Edit a workflow (natural language)

The user wants to change a workflow's steps in plain English. Turn that into a clean revision that takes effect everywhere, including any schedule that uses it.

## Step 1: Resolve the target workflow

Identify which workflow the user means.

- If they reference one by name/slug ("the SEO workflow", "seo-content-brief-drafter"), call **`get_workflow`** with `{ slug, source }` (source defaults to `web-seed`; for a workflow they generated, use `generated`). If unsure which, call **`list_workflows`** and match by name.
- If they say "this workflow" mid-conversation, use the one most recently discussed (its `workflow_id` from a prior `get_workflow` / `apply_workflow`).

You need the workflow's **`id`** and its **current `steps`** (from `get_workflow`).

## Step 2: Compose the FULL revised step chain

Build the **complete** new step list, not a diff: take the current steps and apply the user's change (add / replace / reorder / remove). Each step is `{ order, intent, kind, integration?, fallbacks? }`:

- `intent`: a verb-led, concrete action ("pull google search console performance: top queries and pages by impressions, CTR, position").
- `kind`: `skill` (bind to a verified skill), `tool` (an integration / Chrome-MCP / API action, carry `fallbacks`), or `decision` (pure logic / approval gate).
- For a tool step that has a specific integration, set `integration` ({source,slug} or a query string); otherwise leave it for the model / Chrome MCP and give `fallbacks` (a manual path).

Keep the user's intent faithful. Anything touching a real client should still end at a `decision` approval gate.

## Step 3: Apply the revision

Call **`revise_workflow`** with `{ workflow_id, steps, summary }` where `summary` is one line describing the change (e.g. "added a Search Console pull + an edit-existing-page action").

The tool:
- **Binds** the new/changed steps to verified skills (the same verify gate + outcome prior as generation), so new steps are real, not unbound.
- If this is the user's own generated workflow → **revises it in place** (a new changelog version).
- If it is a shared/curated (`web-seed`) workflow → **forks it into the user's own editable copy** (so the edit is theirs and survives re-seeds) and **re-points the user's schedules** that targeted the original at the fork.

## Step 4: Report (one short paragraph)

Tell the user, in plain language:
- what changed (the steps added/replaced),
- whether it was revised in place or **forked into their own copy** (mention the new slug),
- how many of their **schedules were re-pointed** (if any), and
- that **the next scheduled run will use the updated workflow automatically**: no re-scheduling, no prompt edit.

Then surface the workflow URL (`url` from the tool) so they can see it.

## Notes

- **Bound coverage may be < 100%.** If `revise_workflow` reports unbound steps (no skill matched the intent), say so plainly: those steps run with the model filling them. That is honest, not a failure.
- **Do not edit a workflow the user did not ask to change.** One request = one revision.
- **This is the "just say it" path.** Because schedules point at the workflow by id and the fork re-points them, the user never has to touch a routine prompt to change what a scheduled workflow does.
