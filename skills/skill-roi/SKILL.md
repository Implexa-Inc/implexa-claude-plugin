---
description: 'Show which org skills are driving attributed outcomes — invocations, unique users, attributed deals/placements/contracts, attributed dollar value. Use when the user says "skill ROI", "which skills are working", "skill performance", "what''s our skill scoreboard", "which skills are driving revenue", "show skill outcomes", or "are our saved skills actually being used". Also accepts manual outcome attribution: "the Acme deal closed yesterday because of skill X — record it." This is the differentiator slide of the Skill Graph — only Implexa can show this because only Implexa sees the systems of record (Salesforce, HubSpot, Bullhorn, Workday) AND the skill invocations.'
---

# Skill ROI — outcome attribution rollup

## Step 1 — Decide read vs write

If the user is asking to SEE the rollup ("show ROI", "which skills are working") → use **mode="roi"** (read).

If the user is reporting an outcome to attribute ("the Acme deal closed", "Pinnacle just placed Jane") → use **mode="write"** (record).

## Step 2a — Read mode (default)

Call **`attribute_skill_outcome`** with:
- `mode: "roi"`
- `sinceDays`: 30 default; the user may specify ("last 7 days", "year to date" → 365)
- `limit`: 25 default

Render the rollup as a clean table sorted by attributedValueUsd desc. Columns:

| Skill | Used | Unique users | Attributed outcomes | Attributed value |
|-------|------|--------------|---------------------|------------------|

Below the table, surface the totals:
- **N active skills** in your org
- **X attributed outcomes** in the window
- **$Y attributed value** (sum)

If the totals are 0: tell the user *"No outcomes attributed yet. Either skills haven't fired enough, or the system-of-record webhooks aren't wired up. Ask Implexa support to confirm Salesforce / Bullhorn webhook ingestion is active."*

## Step 2b — Write mode (manual attribution)

If the user is reporting an outcome ("Acme deal closed yesterday — credit it to skill X"), call **`attribute_skill_outcome`** with:
- `mode: "write"`
- `source`: which system the outcome came from (`salesforce` / `hubspot` / `bullhorn` / `workday` / `manual`)
- `eventType`: e.g. `opportunity_closed_won`, `placement_created`, `deal_closed`
- `eventOccurredAt`: ISO timestamp
- `entityType`: e.g. `Opportunity`, `Placement`, `Deal`
- `entityId`: source-system entity ID
- `outcomeValueUsd`: the dollar value
- `attributionKeys`: ALL identifiers you can extract from context (`accountId`, `opportunityId`, `candidateId`, `companyDomain`, `contactEmail`)

The tool will look back 30 days for a matching skill invocation by ANY of the keys you pass. If found: it's attributed (you'll be told to whom + how long ago). If not found: recorded but unattributed.

Tell the user the attribution result clearly. Don't fabricate attribution if the tool says "unattributed."

## Step 3 — Recommend the next move

If you ran read mode and saw skills that aren't being used: suggest the user reshare or improve them.
If you ran write mode and the outcome wasn't attributed: explain that no recent skill invocation matched — the user may have done the work outside Implexa.
If everything looks good: suggest the user save another high-value workflow with `/implexa:save-this`.

## What's next?

- `Show skill ROI for the last 7 days`
- `Save another workflow as a skill`
- `Show the team's most-used skills`

## Notes for the model

- **Don't fabricate dollar values.** If the source system didn't report one, leave outcomeValueUsd null. Honest "outcome recorded, value unknown" beats a made-up $50K.
- **Last-touch attribution** is V1. The most recent matching invocation gets the credit. If multiple skills touched the same entity, only the latest one is attributed.
- **30-day window** is the default. The user can override with `attributionWindowDays`.
- **Webhook ingestion is the production path.** This MCP tool is for demos + manual attribution + LLM-observed outcomes (e.g. "I see a deal close mention in the call transcript — record it").

## Error handling

| Error                                       | Diagnosis                          | Tell the user                                                                                                |
|---------------------------------------------|------------------------------------|--------------------------------------------------------------------------------------------------------------|
| `For write mode: source, eventType, ... required` | Missing required fields for write  | Loop back and ask the user for the missing fields.                                                           |
| `duplicate: true`                           | Same outcome already recorded      | Silent OK — tell the user "Already recorded (idempotent)." Skip if obvious from context.                     |
| `attributionStatus: unattributed`            | No matching invocation in window   | "Outcome recorded, but no skill invocation matched in the 30-day window. The work may have happened outside Implexa." |
