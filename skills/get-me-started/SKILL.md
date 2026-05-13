---
description: First-time user activation flow — get a polished result in under 10 minutes by running a base Playbook against the user's real data. Use when the user says "get me started", "show me what Implexa does", "first time using this", "what can you do for me", "demo this", "show me a quick win", or just installed Implexa for the first time. The activation hook that converts curiosity into adoption — paste a prospect/company/role → run a base Playbook end-to-end → polished output → save as your version → first skill in your library.
---

# Get me started — your first 10 minutes with Implexa

The user just installed Implexa (or wants to see what it does). Get them a polished, useful result in under 10 minutes by running a real workflow against real data they care about, then leaving them with a saved skill they can run again.

## Step 1 — Pick the right Playbook for them

Start by asking ONE question:

> *"To show you what Implexa does, paste any of these:*
> - *A prospect or company you're trying to research (we'll do account research)*
> - *A specific role you're hiring for (we'll source candidates)*
> - *A meeting on your calendar this week (we'll do pre-call prep)*
>
> *Or just say 'surprise me' and I'll pick something useful."*

Map their input to one of the horizontal base Playbooks Implexa seeds (call **`list_org_skills`** to find the exact slugs available — they ship with every install):

| User pasted | Playbook to fire |
|---|---|
| Company name / domain / LinkedIn URL | `research-this-company` |
| Job description / role title | `source-candidates-for-role` |
| Meeting topic / calendar event | `pre-meeting-prep` |
| Person's name / email | `research-this-person` |
| Topic / question / "research X" | `research-a-topic` |
| "Surprise me" / nothing specific | Pick whichever Playbook has the highest `attributedOutcomes` from the list_org_skills response |

## Step 2 — Run the Playbook end-to-end

Call **`apply_org_skill`** with the selected slug + invocationArgs containing whatever the user pasted. The Playbook will chain the appropriate external-data tools.

While it runs, narrate briefly what's happening: *"Pulling company info... finding decision-makers... enriching contacts... drafting outreach..."* — this is the demoable moment.

## Step 3 — Show the polished result

Render the output cleanly. Don't dump JSON — make it look like something they'd actually send/use:

- Account research: a brief summary + ranked stakeholder list + suggested talking points
- Candidate sourcing: ranked candidate list with why-fit reasoning + contact info
- Pre-call prep: agenda + attendee context + recent activity + suggested questions
- Person lookup: enriched profile + recent activity + how to reach them

Also surface what just happened under the hood, briefly:
> *"That used 4 external-data tools chained together. Manually this would have taken about 15 minutes — Implexa did it in 90 seconds."*

## Step 4 — Convert to a personalized skill

This is the activation moment. Ask:

> *"Save this as YOUR version of this skill? You can customize it later — your tone, your favorite data sources, your preferred output format."*

If yes → call **`fork_org_skill`** with:
- `sourceSkillId`: the slug they just ran (it's a system Playbook)
- `scope`: 'private' (their own copy) — or 'org' if they want to share immediately
- `personalizations`: optional — anything from the conversation that suggests customization (e.g. "they always emphasize technical fit")

The fork creates a private copy in their org_skills they can now invoke + tweak.

## Step 5 — What's next

End with a clear menu of next moves. Don't list everything — give 3 strong options:

> *"You're set up. Three things you can try next:*
> 1. *Run your new skill against another company / candidate / meeting*
> 2. *Browse the other base Playbooks we ship — `/implexa:playbooks`*
> 3. *Build a custom skill by demonstrating a workflow once — `/implexa:record-skill`*"*

## What's next?

- `Run my new skill on a different company`
- `Show me what other Playbooks Implexa ships with`
- `Save my next workflow as a custom skill`

## Notes for the model

- **The 10-minute target is real.** If you hit any error or the user's input is unclear, ask once for clarification and proceed. Don't get stuck in loops — better to ship a partial result than waste their time.
- **Don't run more than one Playbook in this flow.** They wanted to see what Implexa does, not get buried in output. One run, one polished result, one saved skill. That's the activation.
- **If list_org_skills returns no system Playbooks**, the seed script hasn't been run yet on this backend. Tell the user: *"I'm in dev mode — base Playbooks aren't loaded. Try /implexa:record-skill instead to build your first skill."*
- **The fork at the end is the hook.** Without it, they used Implexa once and got a result. With it, they have a personal asset they own. Don't skip Step 4.

## Error handling

| Error                              | Diagnosis                  | Tell the user                                                                                                |
|------------------------------------|----------------------------|---------------------------------------------------------------------------------------------------------------|
| Playbook execution failed mid-run  | One of the chained tools errored | Surface the failed step + suggest they retry with a slightly different input.                                  |
| User pasted ambiguous input        | Couldn't pick a Playbook   | Ask one clarifying question (e.g. "is this a company or a person?"), then proceed.                            |
| `fork_org_skill` failed            | Source skill not found / RBAC issue | Skip the fork silently; tell user "your result is above — want to save your next workflow as a skill instead?" |
| No system Playbooks loaded         | Backend hasn't seeded      | Pivot to /implexa:record-skill for first skill creation.                                                |
