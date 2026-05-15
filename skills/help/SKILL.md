---
description: Show example prompts and tips for using the Implexa plugin. Manual-only — user must explicitly type /implexa:help.
disable-model-invocation: true
---

# Implexa plugin — quick reference

When the user invokes `/implexa:help`, present the content below VERBATIM as a markdown reply. Don't paraphrase, don't expand, don't add your own commentary — just print this catalogue. The user is asking *what can I do?* and wants a scannable list of working prompts they can copy.

If the user passed any text after `/implexa:help` (in `$ARGUMENTS`), and it matches one of the section names below (e.g. "record", "share", "browse"), filter to just that section. Otherwise show everything.

---

# Implexa — what can I do?

Implexa captures workflows you do once and turns them into reusable, shareable, measurable skills. Below are example prompts that demonstrate the platform.

## 🎬 Record a skill (the killer flow)

The core action. Demonstrate a workflow once, get a structured skill back.

- `/implexa:record-skill` — start recording. Tell Implexa the intent, then do your work normally. Hit "stop" when done. You'll be interviewed for 2–4 gap-filling questions, then the skill is saved.
- `Watch me research this company and save the workflow` — same as above, naturally phrased.
- `I want to show you a workflow once and have you save it` — same.

**What gets captured during a demo:**
- Every Implexa MCP tool you (or Claude) invoke
- Every non-Implexa action you log via `record_demo_note` (WebSearch, file reads, manual reasoning)
- The full user-prompt + assistant-response transcript (via Claude Code hooks)
- The "anything else?" free-text capture, if you mention out-of-Claude activity

## 📂 Browse + invoke saved skills

- `Run my triage skill` → calls `/implexa:run` (fuzzy-matches + applies — preferred)
- `Use my Implexa skill for outreach` → calls `/implexa:run`
- `Show me my skills` → calls `/implexa:my-skills` (your personal library — browse only)
- `Show me my org's skills` → calls `/implexa:org-skills` (team-wide view — browse only)
- `What skills have I saved?` → calls `/implexa:my-skills`
- `Browse the Implexa Playbooks` → calls `/implexa:playbooks`
- `What workflows has my team built?`

## 🔗 Share a skill (viral)

Two modes — team-gated (same email domain) or public (anyone).

- `/implexa:share-this` — generate a share link
- `Share my last skill with my team` — team-gated link to your domain
- `Share my "research-this-company" skill publicly` — public link, paste anywhere
- `Post this skill on LinkedIn` — public-mode share
- `Revoke that share link I just made`

## 🌱 Fork a skill into your org

- `Fork the "research-a-topic" Playbook for me to customize`
- `/implexa:fork research-this-company`
- `Make my own version of <slug>`

Forking creates a private editable copy in your org. Activate it org-wide when ready.

## 📈 Outcome attribution + ROI

- `Show me which skills are working` → calls `/implexa:skill-roi`
- `What's my Implexa ROI?`
- `Which of my skills has driven the most outcomes?`
- `Manually attribute today's closed deal to my "land-the-meeting" skill`

## 💾 Save the workflow I just did

Post-hoc capture (no demo flow required).

- `/implexa:save-this` — turn the current Claude session into a skill
- `Save what we just did as a workflow`
- `Make that a skill so I can do it again`

## 🚀 First-time setup

- `/implexa:get-me-started` — first-run activation; pick a Playbook, run it, save your forked version
- `/implexa:setup` — connect integrations (email, calendar, future: CRM)
- `/implexa:credits` — check credit balance + plan tier
- `/implexa:help` — this page

---

## Pro tips

- **Recording captures everything** — you don't need to call `record_demo_note` for Implexa tools (auto-captured) or your typed prompts (host hook). Only call it for things you do "in your head" or in another tool you want to log.
- **Free first** — `list_org_skills`, `apply_org_skill`, `get_credits`, and viewing share previews are all free. Skill capture, interview, share-link creation, and Fiber/Coresignal/Apollo data lookups consume credits.
- **Outcome attribution is automatic when CRM is connected** — closing a deal in Salesforce within 30 days of running a skill attributes back. Or use `attribute_skill_outcome` to record manually.
- **Skills travel with their lineage** — fork → fork → fork preserves provenance. The dashboard shows where every skill came from.

## v1 MCP tools available (~26)

### 🎯 Skill Graph (11)
`start_demonstration` · `end_demonstration` · `interview_for_skill` · `record_demo_note` · `record_demo_freetext` · `list_org_skills` · `apply_org_skill` · `fork_org_skill` · `capture_workflow_as_skill` · `attribute_skill_outcome` · `create_share_link`

### 🔎 External data — Fiber + Coresignal + Apollo (14)
`find_accounts` · `find_accounts_by_signals` · `find_prospects` · `find_prospects_by_career_history` · `find_person` · `find_job_postings` · `lookup_company` · `lookup_domain` · `lookup_email` · `lookup_person` · `lookup_linkedin_posts` · `enrich_contacts` · `get_enriched_contacts` · `nl_combined_search`

### ✍️ Generation (1)
`draft_message` — direct Anthropic-SDK message draft for emails / DMs / posts. No saved-agent abstraction; just give it tone + intent.

### 💰 Admin (1+)
`get_credits` — check credit balance, plan tier, monthly quota, low-balance warning.

## Slash command reference

| Command | What it does |
|---|---|
| `/implexa:record-skill` | Start a demonstration recording → save as structured skill |
| `/implexa:save-this` | Post-hoc capture of current session |
| `/implexa:run` | **Find + run** a saved skill (fuzzy matches your query — preferred path for skill reuse) |
| `/implexa:my-skills` | **Browse** skills YOU authored (personal library) |
| `/implexa:org-skills` | **Browse** your org's full skill library (everyone's) |
| `/implexa:playbooks` | Browse the horizontal Playbook library |
| `/implexa:fork <slug>` | Clone a skill into your org for customization |
| `/implexa:share-this` | Generate a share link (team-gated or public) |
| `/implexa:skill-roi` | Outcome attribution rollup |
| `/implexa:get-me-started` | First-run activation flow |
| `/implexa:credits` | Credit balance + plan tier |
| `/implexa:setup` | Connect integrations / rotate API keys |
| `/implexa:help` | This page |

## Common patterns

**1. "I do this every week — save me time."**
Run `/implexa:record-skill`, demonstrate the workflow once, finalize as an org skill. Next week, just say "run my <skill-slug>".

**2. "My teammate built a great workflow — I want it."**
Have them run `/implexa:share-this` with `team` mode. You install in one click after signup, and the skill appears in `/implexa:org-skills`.

**3. "Show this skill to the world."**
After saving, say `share publicly`. Implexa scrubs PII (email, phone, API keys, credit-card shapes) and gives you a public preview URL with outcome stats — paste in Slack, LinkedIn, X.

**4. "Which of my skills is actually working?"**
`/implexa:skill-roi` returns invocations, attributed outcomes, and attributed $ value. Tells you what to double down on vs. archive.
