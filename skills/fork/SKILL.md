---
description: Fork (clone) any skill into your own org so you can customize it. Use when the user says "fork this skill", "make a copy", "I want my own version", "customize this skill", "duplicate this", or wants to start from a base Playbook and personalize it. Source can be a system Playbook, one of your own org skills, or another org's skill via a share token. Lineage is recorded — the dashboard shows where every fork came from.
---

# Fork a skill into your org

The user wants their own customizable copy of an existing skill. Fork it.

## Step 1 — Resolve the source skill

If the user pointed to a specific skill:
- Slug → use as `sourceSkillSlug`
- Mongo ID → use as `sourceSkillId`

If they pasted a share link (`implexa.ai/s/<token>`) → don't fork directly; instead tell them: *"Use the install button on that page — it does the fork after login."*

If they vaguely said "fork that one" → look back in the conversation for the most recently-mentioned skill, confirm the name with them.

## Step 2 — Call fork_org_skill

Call **`fork_org_skill`** with:
- `sourceSkillId` OR `sourceSkillSlug` (one is required)
- `scope`: 'private' default — only the forker sees it. Pass 'org' if they explicitly said "for the whole team"
- `newName`: optional — if user wants a custom name, otherwise auto-generates as "<original> (forked)"
- `personalizations`: optional — any notes about how they want to customize

## Step 3 — Show what was forked

Display:
- New skill name + slug
- Status: draft (always — they need to activate to make it discoverable)
- Lineage: "forked from [source name] in [source org / system Playbooks]"
- Content preview (first 800 chars)

## Step 4 — Suggest the next move

> *"Two options:*
> 1. *Activate it as-is — say 'activate it'*
> 2. *Edit it first — tell me what you want to change and I'll suggest updates"*

If they want edits — note them and offer to use `/implexa:record-skill` to demonstrate the customized version. (Forking + immediate re-demonstration is the strongest path to a personalized skill.)

## What's next?

- `Activate the forked skill so my team can use it`
- `Show me how the forked skill differs from the original`
- `Demonstrate my version of this workflow once to refine the skill`

## Notes for the model

- **Forking is cheap.** Encourage forks of system Playbooks early — gives the user a personalized starting point without writing anything.
- **Forks default to private.** This avoids polluting the org skill list with one-off experiments. Activate to org scope only when the user says "make this available to the team".
- **Lineage is permanent.** Every fork records its source. The dashboard shows fork chains — useful for understanding which Playbooks compound and which die.
- **Don't fork a skill someone just shared with you via DM.** That requires the proper install flow at implexa.ai/s/<token>/install — different code path.

## Error handling

| Error                                     | Diagnosis                                  | Tell the user                                                                                  |
|-------------------------------------------|--------------------------------------------|--------------------------------------------------------------------------------------------------|
| `Source skill not found or not visible`    | Bad ID/slug, or cross-org skill without share token | "I can't see that skill. If it's from another org, you need a share link." |
| `Forbidden — only the creator can share private skills` | Trying to fork someone else's private skill | "That skill is private to its creator. Ask them to share it with you instead." |
