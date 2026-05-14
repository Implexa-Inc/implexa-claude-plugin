---
description: First-time setup — get an Implexa API key and configure it. Also self-diagnoses connection problems (key not set, invalid key, plugin not loaded). Manual-only — user must explicitly type /implexa:setup.
disable-model-invocation: true
---

# Implexa setup & diagnostics

User invoked `/implexa:setup`. This is BOTH the first-run onboarding flow AND the diagnostic / "something's broken" troubleshooter. Branch based on what the user's situation actually is.

## Step 1 — Probe whether the MCP is connected

Call **`get_credits`** (free, no-side-effect tool). Observe the result:

| Outcome | Diagnosis | Branch to |
|---|---|---|
| Returns successfully (plan / quota info in payload) | Key is valid + connected | **Branch A: "You're set up"** |
| No `mcp__plugin_implexa_implexa__*` tools available at all | Plugin's MCP server didn't start (most likely: `IMPLEXA_API_KEY` env var missing in the app's process env) | **Branch B: "Let's get you connected"** |
| Returns 401 / "Invalid API key" / "API key has been revoked" | Key is configured but invalid | **Branch C: "Your key needs replacing"** |
| Returns `INSUFFICIENT_QUOTA` or 429 | Hit the monthly skill creation limit (Free plan = 5/month) | **Branch D: "Monthly limit reached"** |

If you can't tell which branch from the response, default to **Branch B** — the most common failure mode.

---

## Branch A — "You're set up" ✅

Show:

> ### ✅ You're connected to Implexa
>
> - **Plan**: `<plan from get_credits>` (e.g. Free, Pro, Enterprise)
> - **Skills created this month**: `<created>` / `<quota>`
> - **Total skills in your library**: `<library_count>` (if available)
>
> Everything looks good. You can record your first skill with `/implexa:record-skill`, or see what else is possible with `/implexa:help`.

End with **"What's next?"** suggestions:

## What's next?

- `Record a skill — /implexa:record-skill`
- `Show me skills my team has shared`
- `Open https://app.implexa.ai/skills`

---

## Branch B — "Let's get you connected" 🆕

This is the canonical onboarding flow AND the "MCP not loaded" diagnostic. Walk the user through the recommended automated setup, with a manual fallback if their environment is unusual.

> ### 🆕 Let's get you connected
>
> The Implexa MCP tools aren't loaded in this session yet. This is almost always because `IMPLEXA_API_KEY` isn't in the process environment that spawned this Claude session.
>
> **The fastest fix** — run our installer (handles both hooks + env vars):
>
> ```bash
> curl -sL https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/install-user-hooks.sh | bash
> ```
>
> When prompted, paste your API key from **https://app.implexa.ai/settings/api-keys** (free signup at **https://app.implexa.ai/signup** — no credit card). Your key starts with `imp_live_`.
>
> #### After the installer runs
>
> 1. **Fully quit Claude** — Cmd+Q on Mac (not just close the window). The MCP server reads the env var on launch, so a fresh process is required.
> 2. Relaunch Claude (Desktop, Cowork, or CLI — whichever you're using).
> 3. Re-run `/implexa:setup` — you should see the green checkmark.
>
> #### If the installer can't run (offline / corporate restrictions / CLI-only)
>
> Manually export the key in your shell:
>
> ```bash
> # zsh (default on macOS):
> echo 'export IMPLEXA_API_KEY="imp_live_..."' >> ~/.zshrc
> source ~/.zshrc
>
> # bash:
> echo 'export IMPLEXA_API_KEY="imp_live_..."' >> ~/.bashrc
> source ~/.bashrc
> ```
>
> For Claude **Desktop** or **Cowork** (GUI apps don't inherit shell env), also run:
>
> ```bash
> launchctl setenv IMPLEXA_API_KEY "imp_live_..."
> ```
>
> Then Cmd+Q and relaunch Claude.

End with **"What's next?"**:

## What's next?

- `/implexa:setup` (re-run after configuring the key)
- `Open https://app.implexa.ai/install`
- `Open https://app.implexa.ai/signup`

---

## Branch C — "Your key needs replacing" 🔁

> ### ⚠️ Your API key isn't working
>
> The key is configured but Implexa rejected it. Two most-likely causes:
>
> 1. **Key was revoked** — someone (maybe you?) clicked Revoke on it. See active keys at **https://app.implexa.ai/settings/api-keys**.
> 2. **Key was rotated** — you regenerated and the new value didn't get into your env.
>
> **Fix**: mint a new key at **https://app.implexa.ai/settings/api-keys** → "Create a key", then re-run the installer:
>
> ```bash
> curl -sL https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/install-user-hooks.sh | bash
> ```
>
> It's idempotent — safe to re-run anytime. Paste the new key when prompted, then Cmd+Q + relaunch Claude.

End with **"What's next?"**:

## What's next?

- `Open https://app.implexa.ai/settings/api-keys`
- `/implexa:setup` (re-run after rotating the key)

---

## Branch D — "Monthly limit reached" 📊

> ### 📊 You've hit your monthly skill creation limit
>
> Implexa Free includes **5 new skills per month** plus **unlimited use** of skills already in your library. You've used all 5 for this month — the counter resets on the 1st.
>
> **Upgrade to Pro** for unlimited skill creation: **https://app.implexa.ai/pricing**
>
> Or wait until the counter resets — your existing skills keep working in the meantime, including any shared with you by your team.

End with **"What's next?"**:

## What's next?

- `Open https://app.implexa.ai/pricing`
- `Show me what skills I can still use this month`
- `/implexa:help` (other things that don't count against the quota)

---

## Notes for the model

- This skill is the on-ramp + diagnostic. **Don't skip the probe in Step 1** — branching from a fake assumption ("looks like Branch B" without trying `get_credits`) gives the wrong advice if the key actually is set.
- Be SHORT. Each branch should be < 200 words shown to the user. They're trying to start working, not read documentation.
- For Branch B, **recommend the installer first** — it handles both the hooks AND the launchctl env var, which is what most Desktop/Cowork users actually need. The manual shell-env path is the fallback for unusual environments.
- Don't shame the user for a revoked key — common situation, especially for keys older than a few months.
- Key prefix is `imp_live_` for production. If you see `rvk_live_` that's a Revenoid key, not Implexa — gently redirect.
