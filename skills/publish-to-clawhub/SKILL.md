---
description: Publish one of your Implexa skills to the ClawHub public marketplace in one shot. Wraps the 5 manual steps (whoami → fetch SKILL.md → stage → clawhub publish → return URL) into a single slash command. Use when the user says "publish to clawhub", "publish my X skill to clawhub", "ship X to clawhub", "put X on clawhub", "publish this skill", "publish my last skill to clawhub", or invokes /implexa:publish-to-clawhub. Defaults version to 0.1.0 for first publish (or auto-increments patch via `clawhub inspect` for re-publishes), defaults tags to the skill's existing tags, defaults owner to the user's clawhub handle. Prompts for a clawscan-note only when the skill uses Chrome MCP / browser-control / unusual MCPs. ClawHub is public-only — rejects org / private scoped skills with a clear explanation.
---

# Publish a skill to the ClawHub marketplace

The user wants to ship one of their Implexa skills to clawhub.ai so anyone can discover and install it. This skill walks through 8 steps: parse args → verify identity → fetch skill → confirm → stage → clawscan check → publish → return URL.

## Step 1 — Parse args

Usage:
```
/implexa:publish-to-clawhub <slug> [--version <semver>] [--tags <comma-list>] [--changelog "<text>"] [--clawscan-note "<text>"] [--owner <handle>] [--dry-run]
```

Required:
- `<slug>` — the skill's slug in the user's Implexa library (kebab-case). Positional, first arg.

Optional:
- `--version` — semver. Default: `0.1.0` for first publish, auto-increment patch for re-publishes (see Step 6).
- `--tags` — comma-separated. Default: pull from the skill's `tags` field.
- `--changelog` — release notes. Default: prompt the user when missing.
- `--clawscan-note` — context for clawscan. Default: only prompt if Step 5 heuristic fires.
- `--owner` — clawhub publisher handle. Default: the `clawhub whoami` output (e.g. `rabgpt`).
- `--dry-run` — build and print the final `clawhub publish` command without running it. Use this for testing.

If the user invoked the command with no slug, ask: "which skill do you want to publish to clawhub? give me the slug (kebab-case)."

## Step 2 — Verify ClawHub identity

Run `clawhub whoami` via Bash. Three outcomes:

- **logged in** → output is a handle (e.g. `✔ rabgpt`). capture it as `clawhubHandle`, surface it to the user briefly: "publishing as rabgpt".
- **logged out / no token** → tell the user: "not logged into clawhub. run `clawhub login` first, then re-invoke this command." stop.
- **token expired** → same as logged out. stop.

ClawHub identity is independent of Implexa identity. Don't try to reconcile.

## Step 3 — Fetch the skill content from Implexa

Call `mcp__implexa__get_skill_content` with `{ slug: <user-supplied slug> }`.

If `ok: false` → surface the error verbatim (it's already user-friendly: "skill <slug> not found in your library. fork or install it first."). Stop.

If `ok: true` → surface a one-block summary:

```
about to publish:
  name:     <name>
  slug:     <slug>
  version:  <current-implexa-version> → <target-clawhub-version>
  scope:    <scope>
  status:   <status>
  tags:     [<tags>]
  triggers: [first 3 trigger phrases]
```

**Reject if scope is `private` or `org`**: "<slug> is scoped <scope>. clawhub is a public marketplace — only universal or system skills can publish. promote scope first via update_org_skill, or skip this one." Stop.

**Reject if status is `archived`**: "<slug> is archived. activate it first via activate_skill (or `/implexa:run` route), then re-invoke." Stop.

## Step 4 — Confirm with the user

Use AskUserQuestion (or a plain yes/no prompt if AskUserQuestion isn't available):

> "publish <name> to clawhub as <owner>/<slug> v<targetVersion>?"

If no → stop, don't stage, don't publish.
If yes → proceed.

## Step 5 — ClawScan heuristic

Scan the fetched `content` string for any of these red flags:

- `mcp__plugin_engineering_slack` or `mcp__Claude_in_Chrome` or `mcp__claude-in-chrome`
- `browser_batch`, `javascript_tool`, `read_console_messages`, `read_network_requests` (chrome MCP surface)
- raw API tokens / bearer secrets (look for `Bearer `, `sk-`, `ghp_`, `xoxb-`, `sk_live_`, `sk_test_`)
- network calls outside the safe list (`implexa.ai`, `anthropic.com`, `agentskills.io`, `clawhub.ai`, `github.com`, `slack.com`, well-known SaaS domains)

If anything fires AND the user didn't pass `--clawscan-note`:
- tell the user which flag fired ("your skill uses Chrome MCP — ClawScan will flag this as unusual")
- ask: "add a clawscan-note explaining why? yes / no / skip"
  - **yes** → prompt for the note, capture as `clawscanNote`
  - **no** / **skip** → proceed without (clawscan may flag in marketplace review — that's fine, manual review handles it)

If `--clawscan-note` was supplied, use it as-is. No re-prompt.

If nothing flagged AND no `--clawscan-note` supplied, no prompt. Continue.

## Step 6 — Resolve target version

If `--version` was supplied → use it as-is.

Otherwise:
- Run `clawhub inspect <slug> --json 2>/dev/null` via Bash. Two outcomes:
  - **not found** (CLI returns an error or empty) → first publish. Target version = `0.1.0`.
  - **found** → parse the latest version, increment patch (e.g. `0.1.4` → `0.1.5`). If you can't reliably parse, fall back to asking the user.

If this is a re-publish AND `--changelog` was NOT supplied, ask: "this is a re-publish (v<latest> → v<target>). add a one-line changelog?" Capture as `changelog`. Empty answer is fine — skip the flag.

If this is a first publish (v0.1.0) AND `--changelog` was NOT supplied, default `changelog` to `"initial publish"`. Don't prompt.

## Step 7 — Stage the bundle

Run via Bash:

```bash
mkdir -p /Users/rabigupta/revenoid-workspace/Implexa/clawhub-publish/<slug>
```

Then write the SKILL.md content using a heredoc:

```bash
cat > /Users/rabigupta/revenoid-workspace/Implexa/clawhub-publish/<slug>/SKILL.md <<'CLAWHUB_EOF'
<content from get_skill_content>
CLAWHUB_EOF
```

**Important**: the content includes a YAML frontmatter block (`---` ... `---`). The heredoc with quoted delimiter (`'CLAWHUB_EOF'`) prevents shell interpolation. Don't change the delimiter to unquoted.

Verify via `ls -la /Users/rabigupta/revenoid-workspace/Implexa/clawhub-publish/<slug>/SKILL.md` — confirm size > 0 bytes.

## Step 8 — Build + run the publish command

Construct the command:

```bash
clawhub publish /Users/rabigupta/revenoid-workspace/Implexa/clawhub-publish/<slug> \
  --slug <slug> \
  --name "<name>" \
  --owner <owner> \
  --version <targetVersion> \
  --tags "<comma-joined-tags>" \
  --changelog "<changelog>" \
  [--clawscan-note "<note>"]
```

Notes:
- `--owner` defaults to the `clawhubHandle` from Step 2 unless `--owner` was passed.
- `--clawscan-note` only included if you have one (from Step 5 or arg).
- Quote strings with spaces. Tags is comma-joined without spaces (`x,twitter,engagement`).

Surface the final command to the user one more time:

> "final command:
> ```
> <full command, line-wrapped>
> ```
> ship it? yes / no"

If **--dry-run** was supplied OR user says no → print the command, do NOT execute. End there.

If yes → run via Bash. Stream the output.

## Step 9 — Verify + return URL

Parse the CLI output for the marketplace URL. ClawHub publish output usually contains a `https://clawhub.ai/skills/<owner>/<slug>` line. If you can't find it, construct it: `https://clawhub.ai/skills/<owner>/<slug>`.

Surface to the user:

```
✓ published to clawhub
  url:        https://clawhub.ai/skills/<owner>/<slug>
  version:    <targetVersion>
  visibility: public
  tagged:     <tags>
```

Plus one-line CTA:

> "share the url in your community channels, or run `clawhub stats <slug>` tomorrow to see install + star counts."

## What's next?

- `publish another skill`
- `run clawhub stats <slug> tomorrow to see installs`
- `cross-post the marketplace url to discord / x / linkedin`

## Notes for the model

- **Always run `clawhub whoami` first.** Don't skip — token may have expired since last publish. Surfaces real identity, prevents publishing to the wrong owner.
- **ClawHub identity != Implexa identity.** ClawHub uses one handle (e.g. `rabgpt`), Implexa uses another (e.g. `founder-implexa`). Surface the clawhub one. Don't try to reconcile.
- **Public-only.** ClawHub is a public marketplace. `private` and `org` scoped skills can't publish — the workflow rejects them with an explanation, not silently.
- **First publish vs re-publish.** First publish defaults to `0.1.0` and `changelog="initial publish"`. Re-publishes auto-increment the patch via `clawhub inspect` and ask for a changelog. Both flows are non-destructive: republish makes a new version, doesn't overwrite.
- **ClawScan heuristic is a courtesy, not a gate.** If the heuristic fires, prompt for a note. If the user says skip, publish anyway. ClawScan will handle it in marketplace review.
- **Dry-run is your test path.** `--dry-run` prints the final command without executing. Use it to validate arg parsing without burning a version number.
- **Don't auto-push the resulting marketplace url anywhere.** Surface it to the user. They decide where it goes.

## Error handling

| Error                                          | Diagnosis                                | Tell the user                                                                                       |
|------------------------------------------------|------------------------------------------|-----------------------------------------------------------------------------------------------------|
| `clawhub whoami` returns non-zero or "no token"| Not logged into ClawHub                  | "not logged into clawhub. run `clawhub login` first, then re-invoke this command."                  |
| `get_skill_content` returns `ok: false`        | Slug not in user's library               | Surface the error verbatim. Suggest forking or installing first.                                    |
| Scope is `private` or `org`                    | ClawHub is public-only                   | "clawhub is public-only. promote scope to universal first (update_org_skill), or skip this one."    |
| Status is `archived`                           | Can't publish archived skills            | "activate the skill first (activate_skill), then re-invoke."                                        |
| `clawhub publish` exits non-zero               | Network, auth, or schema issue           | Surface stderr verbatim. Don't retry automatically.                                                 |
| `clawhub inspect` parse fails on re-publish    | Output format changed                    | Ask the user: "couldn't auto-increment version. what version should this be? (e.g. 0.2.0)"          |
