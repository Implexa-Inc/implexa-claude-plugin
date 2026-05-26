---
description: 'Generate a share link for any of your skills (or system Playbooks) — recipients can preview the skill and install in 1 click after login. Two modes — TEAM-only (gated to same email domain — only @yourdomain.com can install, perfect for "send this to my team") or PUBLIC (anyone can install, perfect for Slack/Twitter/LinkedIn distribution). Use when the user says "share this skill", "share my skill", "share my last skill", "share with my team", "share my skill with a teammate", "share my skill with a colleague", "share with a teammate", "send this to my team", "send to my team", "DM this skill to someone", "share on Slack", "post on LinkedIn", "post on Twitter", "post on X", "make a link for this", "create a share link", "share with someone", or any other phrasing meaning "give me a link to send this skill to another person." The viral primitive of the Skill Graph — turns a saved skill into a one-click installable artifact across orgs.'
---

# Share a skill — generate a preview + install link

The user wants to share a skill with someone — either their team (domain-gated) or the public (anyone). Generate a `implexa.ai/s/<token>` link they can paste anywhere.

## Step 1 — Resolve the skill to share

If user pointed to a specific skill → use slug or ID.
If they said "share my last skill" → look back in the conversation for the most-recently-created or most-recently-discussed skill, confirm.
If they said "share that Playbook" → confirm which one.

## Step 2 — Pick the share mode

This is the most important question. Ask ONE clear question:

> *"Share this with: (1) your team — only people on your email domain can install, or (2) publicly — anyone with the link can install (PII is removed)?"*

Map their reply:
- *"team"* / *"my team"* / *"colleagues"* / *"internal"* / *"only us"* / *"send to Sarah"* → `shareMode: "team"`
- *"public"* / *"Slack"* / *"LinkedIn"* / *"Twitter"* / *"everyone"* / *"anyone"* → `shareMode: "public"`
- Ambiguous → ask once for clarification, then proceed.

## Step 3 — Optional message + expiry

> *"Want to add a one-line message recipients see in the preview? (e.g. 'this is how I do prospect research now')"*

If they say no, skip. If yes, capture it. For expiry: default is no expiry. Only ask if the user mentions sensitivity ("just for this project", "next 30 days only").

## Step 4 — Call create_share_link

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

## Step 5 — Render the link clearly

Show the URL prominently with the gate clearly stated:

For **team mode**:
```
🔗 Team share link ready:
   https://implexa.ai/s/aBc1d_FgH2

   Only @{domain} email addresses can install. Anyone else hitting this link
   will see the preview but be blocked at the install step.

   Track views + installs in your Skill Graph dashboard.
```

For **public mode**:
```
🔗 Public share link ready:
   https://implexa.ai/s/aBc1d_FgH2

   Anyone with this URL can preview and install. PII has been removed from
   the public payload — your workflow + sample data become visible to other orgs.

   Track views + installs in your Skill Graph dashboard.
```

## Step 6 — Suggest distribution

For **team mode**:
> *"Drop this in your team Slack channel or DM it directly. New teammates without an account get a clean 'sign up with your @{domain} email' flow."*

For **public mode**:
> *"Three places this works really well:*
> 1. *LinkedIn post — skills with strong outcome stats are credibility signals*
> 2. *Twitter / X — short framing ('I built a skill that does X — try it')*
> 3. *Public community Slacks (Pavilion, RevOps Co-op, etc.)"*

## What's next?

- `Show me the share link's view + install stats`
- `Share another skill from my library`
- `Revoke this share link`

## Notes for the model

- **Pick the right mode.** Team mode protects the workflow (only same-domain people install). Public mode trades that protection for reach. Default to team mode when the user mentions specific teammates ("send to Sarah", "for my team"); default to public when they mention social channels ("post on LinkedIn", "share on Twitter").
- **Preview is always public regardless of mode.** Anyone with the URL can SEE the skill content + outcome stats — the gate is only enforced at install time. Make sure the user understands: even team-mode links show the workflow to anyone they share the URL with.
- **PII is already scrubbed at capture time.** But forks/edits can re-introduce sensitive content. Quick gut-check before sharing publicly: does the SKILL.md mention specific deal sizes, customer names, or internal codenames? If yes, edit first.
- **Outcome stats ARE shown on the preview.** "This skill has driven $340K in attributed revenue across 12 users" is the viral hook. Encourage users with strong stats to share aggressively.
- **Personal-email creators can't team-share.** If the user is on gmail/outlook/yahoo, the team-mode call will error. Catch the error and offer public mode instead — don't make the user re-issue.
- **Don't auto-share without explicit confirmation.** Sharing is irreversible-ish (revoke works but the URL may already be in N people's chat history).

## Error handling

| Error                                        | Diagnosis                              | Tell the user                                                                                       |
|----------------------------------------------|----------------------------------------|-------------------------------------------------------------------------------------------------------|
| `Cannot create team share — personal domain` | Creator's email is gmail/outlook/yahoo | "Team shares need a work email — your account is on a personal domain. Want to share publicly instead?" |
| `Cannot create team share — missing an email`| Account has no email on file           | "Couldn't find an email on your account — sharing publicly instead." Retry with shareMode='public'. |
| `Forbidden — only the creator can share private skills` | Trying to share someone else's private | "Only the original creator can share that skill."                                                     |
| `Skill not found`                            | Bad slug/ID                           | Re-confirm the skill name and retry.                                                                  |
| `Token generation collision`                  | Astronomically rare; retry            | Tell the user "weird transient error, trying again" and re-call the tool.                            |
