---
description: 'Share an AGENT you saved. For a single-task agent: generate a team-gated or public install link (implexa.ai/s/<token>). For a whole-job agent: publish it to the community catalog with PII stripped, earning you karma. ONE share verb for both. Use when the user says "share this", "share this agent", "share this skill", "share this workflow", "share my agent", "share my skill", "share my workflow", "share my last agent", "share with my team", "send this to my team", "DM this to someone", "share on Slack", "post on LinkedIn", "post on Twitter", "post on X", "make a link for this", "create a share link", "share with the community", "publish my agent", "share with someone", or any phrasing meaning "let other people use this." The viral primitive: turns a saved agent into something others can install or run.'
---

# Share an agent

ONE share verb, two artifact kinds. First figure out which, then route.

## Step 0: Single-task agent or whole-job agent?

What is the user pointing at?

- A **single-task agent** (a single SKILL.md procedure) → the **Agent path** below: a team-gated or public install link (`implexa.ai/s/<token>`).
- A **whole-job agent** (a whole-job chain they captured or generated, e.g. from `/implexa:my-skills workflows` or one they just saved) → the **Whole-job agent path**: publish to the community catalog with PII stripped, earning karma.

Decide from what was just discussed / created. If genuinely unsure, ask once: *"Is this a single-task agent or a whole-job agent you're sharing?"* Then route. The Whole-job agent path is at the bottom; the Agent path is immediately below.

---

## Agent path: generate a preview + install link

The user wants to share an AGENT with someone, either their team (domain-gated) or the public (anyone). Generate a `implexa.ai/s/<token>` link they can paste anywhere.

## Step 1: Resolve the agent to share

If user pointed to a specific agent → use slug or ID.
If they said "share my last agent" → look back in the conversation for the most-recently-created or most-recently-discussed agent, confirm.
If they said "share that Playbook" → confirm which one.

## Step 2: Pick the share mode

This is the most important question. Ask ONE clear question:

> *"Share this with: (1) your team (only people on your email domain can install), or (2) publicly (anyone with the link can install, PII is removed)?"*

Map their reply:
- *"team"* / *"my team"* / *"colleagues"* / *"internal"* / *"only us"* / *"send to Sarah"* → `shareMode: "team"`
- *"public"* / *"Slack"* / *"LinkedIn"* / *"Twitter"* / *"everyone"* / *"anyone"* → `shareMode: "public"`
- Ambiguous → ask once for clarification, then proceed.

## Step 3: Optional message + expiry

> *"Want to add a one-line message recipients see in the preview? (e.g. 'this is how I do prospect research now')"*

If they say no, skip. If yes, capture it. For expiry: default is no expiry. Only ask if the user mentions sensitivity ("just for this project", "next 30 days only").

## Step 4: Call create_share_link

Call **`create_share_link`** with:
- `skillId` OR `skillSlug`
- `shareMode`: "team" or "public" (from Step 2)
- `shareMessage`: optional, from Step 3
- `expiresInDays`: optional, from Step 3

You'll get back:
- `url`: the preview URL (paste this anywhere)
- `installUrl`: where the install button on the preview points
- `shareMode`: confirms which mode was created
- `allowedEmailDomain`: present for team mode (e.g. "implexa.ai")
- `gateDescription`: human-readable description of the gate

**If the call returns an error containing "personal domain"** (creator has a gmail/outlook/yahoo address and tried team-mode): tell the user *"Team shares require a work email. Want to share publicly instead?"* and retry with `shareMode: "public"`.

## Step 5: Render the link clearly

Show the URL prominently with the gate clearly stated:

For **team mode**:
```
🔗 Team share link ready:
   https://implexa.ai/s/aBc1d_FgH2

   Only @{domain} email addresses can install. Anyone else hitting this link
   will see the preview but be blocked at the install step.

   Track views + installs in your Implexa dashboard.
```

For **public mode**:
```
🔗 Public share link ready:
   https://implexa.ai/s/aBc1d_FgH2

   Anyone with this URL can preview and install. PII has been removed from
   the public payload. Your agent + sample data become visible to other orgs.

   Track views + installs in your Implexa dashboard.
```

## Step 6: Suggest distribution

For **team mode**:
> *"Drop this in your team Slack channel or DM it directly. New teammates without an account get a clean 'sign up with your @{domain} email' flow."*

For **public mode**:
> *"Three places this works really well:*
> 1. *LinkedIn post (agents with strong outcome stats are credibility signals)*
> 2. *Twitter / X (short framing: 'I built an agent that does X, try it')*
> 3. *Public community Slacks (Pavilion, RevOps Co-op, etc.)"*

---

## Whole-job agent path: publish to the community catalog (+ karma)

The user is sharing a WHOLE-JOB AGENT (one they captured or generated). Whole-job agents don't use install links; they publish to the community agent catalog at `implexa.ai/workflows/<slug>`, where anyone can run them. Sharing is opt-in, strips PII, and earns the author karma.

### Step W1: Confirm + genericize (no PII)

Only the author can share their own agent. Before publishing, make it GENERIC, a reusable template, not a record of one private run:
- Rewrite the **name** and **description** to remove any personal specifics (your company, handles, niche, client names, internal codenames). e.g. "My Acme daily reel" → "Daily IG reel: produce and render".
- If a STEP label names a personal specific, fix it first via `revise_workflow` before sharing.

Confirm in one line: *"I'll publish this to the community agent catalog as '<generic name>', with your personal details stripped. You earn karma. Share it?"* Only proceed on an explicit yes.

### Step W2: Call share_workflow

Call **`share_workflow`** with:
- `slug` + `source` (the workflow's source, `community` for captured, `generated` for generated), OR `workflow_id`
- `name`: the genericized name
- `description`: the genericized description

It flips the workflow public, applies the clean copy, marks PII scrubbed, and credits karma. (`unshare: true` reverses it.)

### Step W3: Render the result

```
🌍 Published to the community agent catalog:
   https://implexa.ai/workflows/<slug>

   PII stripped. Anyone can now run this whole job on their own agent.
   +50 karma. See your total at app.implexa.ai/settings/karma.
```

Then suggest distribution (LinkedIn / X / a community Slack), same as a public agent share.

**Never publish an agent without an explicit yes.** Private-by-default is the foundation principle; sharing is the user's choice, every time.

## What's next?

- `Show me the share link's view + install stats`
- `Share another agent from my agents`
- `Revoke this share link` / `Unshare that agent`

## Notes for the model

- **Pick the right mode.** Team mode protects the agent (only same-domain people install). Public mode trades that protection for reach. Default to team mode when the user mentions specific teammates ("send to Sarah", "for my team"); default to public when they mention social channels ("post on LinkedIn", "share on Twitter").
- **Preview is always public regardless of mode.** Anyone with the URL can SEE the agent content + outcome stats. The gate is only enforced at install time. Make sure the user understands: even team-mode links show the agent to anyone they share the URL with.
- **PII is already scrubbed at capture time.** But forks/edits can re-introduce sensitive content. Quick gut-check before sharing publicly: does the SKILL.md mention specific deal sizes, customer names, or internal codenames? If yes, edit first.
- **Outcome stats ARE shown on the preview.** "This agent has driven $340K in attributed revenue across 12 users" is the viral hook. Encourage users with strong stats to share aggressively.
- **Personal-email creators can't team-share.** If the user is on gmail/outlook/yahoo, the team-mode call will error. Catch the error and offer public mode instead, don't make the user re-issue.
- **Don't auto-share without explicit confirmation.** Sharing is irreversible-ish (revoke works but the URL may already be in N people's chat history).

## Error handling

| Error                                        | Diagnosis                              | Tell the user                                                                                       |
|----------------------------------------------|----------------------------------------|-------------------------------------------------------------------------------------------------------|
| `Cannot create team share - personal domain` | Creator's email is gmail/outlook/yahoo | "Team shares need a work email. Your account is on a personal domain. Want to share publicly instead?" |
| `Cannot create team share - missing an email`| Account has no email on file           | "Couldn't find an email on your account, sharing publicly instead." Retry with shareMode='public'. |
| `Forbidden - only the creator can share private skills` | Trying to share someone else's private | "Only the original creator can share that agent."                                                     |
| `Skill not found`                            | Bad slug/ID                           | Re-confirm the agent name and retry.                                                                  |
| `Token generation collision`                  | Astronomically rare; retry            | Tell the user "weird transient error, trying again" and re-call the tool.                            |
