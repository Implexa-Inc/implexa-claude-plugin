---
description: First-time setup — get a Implexa API key and configure IMPLEXA_API_KEY. Also self-diagnoses connection problems (invalid key, expired key, out of credits). Manual-only — user must explicitly type /implexa:setup.
disable-model-invocation: true
---

# Implexa setup & diagnostics

User invoked `/implexa:setup`. This is BOTH the first-run onboarding flow AND the diagnostic / "something's broken" troubleshooter. Branch based on what the user's situation actually is.

## Step 1 — Probe whether the MCP is connected

Call **`get_company_info`** (free, no credit charge). Observe the result:

| Outcome | Diagnosis | Branch to |
|---|---|---|
| Returns successfully (company, ICP, etc. in payload) | Key is valid + connected | **Branch A: "You're set up"** |
| Tool not available at all (no `mcp__plugin_implexa_implexa__*` tools) | Plugin's MCP server didn't start (most likely: env var missing or npm package not installed) | **Branch B: "Let's get you a key"** |
| Returns 401 / "Invalid API key" / "API key has been revoked" | Key is configured but bad | **Branch C: "Your key needs replacing"** |
| Returns `INSUFFICIENT_CREDITS` or 402 | Out of free credits | **Branch D: "Out of credits"** |

If you can't tell which branch from the response, default to **Branch B** — the most common failure mode.

---

## Branch A — "You're set up" ✅

Show:

> ### ✅ You're connected to Implexa
>
> - **Account**: `<company name from get_company_info>`
> - **Active ICP**: `<icp_setting.name>`
> - **Connected integrations**: `<comma list>` (or "None connected — connect from admin.implexa.ai → Settings")
> - **Tracked signals**: `<count>` buying / hiring / fact triggers
>
> Everything looks good. Run `/implexa:help` to see what you can do.

End with the **"What's next?"** suggestions (3 backtick-quoted prompts):

## What's next?

- `Show me what I can do — /implexa:help`
- `Find me 10 accounts that match my ICP`
- `Brief me on my next call`

---

## Branch B — "Let's get you a key" 🆕

This is the canonical first-run flow. Walk the user through three numbered steps. Be concise — they want to start using the tools, not read a novel.

> ### 🆕 Welcome to Implexa
>
> You'll need an API key to call the tools. **Free plan ships with 500 credits** — no credit card required.
>
> #### 1. Sign up (2 min)
>
> Go to **https://admin.implexa.ai/p2p/signup** and create an account (Google / Microsoft SSO works, or email). Complete the onboarding flow that asks about your ICP — that powers most of the tools you're about to use.
>
> #### 2. Generate an API key (30 sec)
>
> Once signed in, open **Settings → API Keys** ([admin.implexa.ai/p2p/settings](https://admin.implexa.ai/p2p/settings)) and click **New key**. Give it a name like "Claude Code" so you recognize it later.
>
> ⚠️ **Copy the key immediately** — it shows once and only once. Looks like: `rvk_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxx`
>
> #### 3. Set it as an env var (one-time)
>
> Pick the snippet for your shell:
>
> **zsh** (default on macOS):
> ```bash
> echo 'export IMPLEXA_API_KEY="rvk_live_..."' >> ~/.zshrc
> source ~/.zshrc
> ```
>
> **bash**:
> ```bash
> echo 'export IMPLEXA_API_KEY="rvk_live_..."' >> ~/.bashrc
> source ~/.bashrc
> ```
>
> **fish**:
> ```bash
> set -Ux IMPLEXA_API_KEY "rvk_live_..."
> ```
>
> **Windows PowerShell** (run as admin once):
> ```powershell
> [Environment]::SetEnvironmentVariable("IMPLEXA_API_KEY", "rvk_live_...", "User")
> ```
>
> #### 4. Restart Claude Code
>
> Exit this session (`/exit` or Ctrl+D) and start `claude` again — the plugin will pick up the env var on next launch.
>
> #### 5. Verify
>
> Run `/implexa:setup` again — you should see the green checkmark.

End with **"What's next?"**:

## What's next?

- `/implexa:setup` (re-run after configuring the key)
- `/implexa:help` (see everything once connected)
- `Open https://admin.implexa.ai/p2p/settings`

---

## Branch C — "Your key needs replacing" 🔁

> ### ⚠️ Your API key isn't working
>
> The key is configured but Implexa rejected it. Two most-likely causes:
>
> 1. **Key was revoked** — someone (maybe you?) clicked the trash icon on it in the dashboard. Active keys are visible at [admin.implexa.ai/p2p/settings](https://admin.implexa.ai/p2p/settings).
> 2. **Key was rotated** — you regenerated and forgot to update the env var.
>
> **Fix**: mint a new key at [admin.implexa.ai/p2p/settings](https://admin.implexa.ai/p2p/settings) → New key, then update your env var:
>
> ```bash
> # zsh — replace existing line in ~/.zshrc, or run:
> sed -i '' '/^export IMPLEXA_API_KEY/d' ~/.zshrc
> echo 'export IMPLEXA_API_KEY="rvk_live_<new key>"' >> ~/.zshrc
> source ~/.zshrc
> ```
>
> Then exit Claude Code and relaunch.

End with **"What's next?"**:

## What's next?

- `Open https://admin.implexa.ai/p2p/settings`
- `/implexa:setup` (re-run after rotating the key)
- `Show me my recently-used keys` (lists active API keys with keyPrefix, so you can identify which key broke)

---

## Branch D — "Out of credits" 💳

> ### 💳 You've run out of Implexa credits
>
> Free plan gets 500 credits to start. Most users go through these in their first week of heavy use.
>
> **Buy more**: [admin.implexa.ai/p2p/billing](https://admin.implexa.ai/p2p/billing)
>
> Plans:
> - **Starter** — 2,000 credits/mo (~$20)
> - **Growth** — 5,500 credits/mo (~$50)
> - **Pro** — 11,000 credits/mo (~$100)
> - **Scale** — 60,000 credits/mo (custom)
>
> All plans roll over unused credits month-to-month.

If you have visibility into their usage breakdown via `get_company_info` or any other source, suggest where credits are going (e.g., "you've used most of your credits on enrichment — consider the Pro plan if you're enriching > 200 contacts/mo").

End with **"What's next?"**:

## What's next?

- `Open https://admin.implexa.ai/p2p/billing`
- `Show me what I've used my credits on` (links to dashboard's Credit Usage page)
- `/implexa:help` (see free tools that don't consume credits)

---

## Notes for the model

- This skill is the on-ramp + diagnostic. **Don't skip the probe in Step 1** — branching from a fake assumption ("looks like Branch B" without trying `get_company_info`) gives the wrong advice if the key actually is set.
- Be SHORT. Each branch should be < 200 words shown to the user. They're trying to start working, not read documentation.
- For Branch B, the platform-specific shell snippets matter — pick the one that matches the user's environment if it's obvious from `$SHELL` (or from the path they ran `claude` from, e.g. `/bin/zsh` vs `/bin/bash`). If not obvious, show all three and let them pick.
- Don't shame the user for an expired/revoked key — common situation, especially for keys older than a few months.
