---
description: 'One-time setup to enable full capture during /implexa:record-skill. Installs user-level hooks needed for Claude Desktop / Cowork (plugin hooks alone don''t fire there). Use when first installing Implexa OR when conversationTurns is 0 in your captured demos. Trigger phrases: setup hooks, enable hooks, fix capture, configure capture, install user hooks.'
---

# Set up host-side capture hooks

The user is installing Implexa for the first time, OR has noticed their captured skills don't include conversation turns / tool calls properly. This skill walks them through the one-time user-level hook setup.

## Why this exists

Implexa's killer feature — capturing every prompt + response + tool call during `/implexa:record-skill` — depends on **host-side hooks** that run on the user's machine.

The plugin ships with hooks at `hooks/hooks.json`, but **Claude Desktop and Cowork sandbox plugin-packaged hooks** (the `--setting-sources user` flag bypasses them). To make capture work on every surface, we install **user-level hooks** in `~/.claude/settings.json` that point to a stable launcher script.

The setup also handles:
- Installing `jq` if missing (required for JSON parsing in the hook)
- Adding Homebrew bin paths to the launcher (GUI processes have a minimal PATH)
- Storing the API key in a config file (GUI processes don't inherit shell env vars)
- Idempotency — safe to re-run

## How to guide the user

Don't try to install the hooks yourself — the script writes to `~/.claude/` which the user should run themselves.

**Tell the user to run this one command in their terminal** (not in this Claude session):

```bash
curl -sL https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/install-user-hooks.sh | bash
```

Then format the output for them clearly:

> 🔧 **Implexa hook setup**
>
> Run this in your terminal (not in Claude):
>
> ```bash
> curl -sL https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/install-user-hooks.sh | bash
> ```
>
> **What it does** (takes ~30 seconds, safe to re-run anytime):
> 1. Installs `jq` if missing (via Homebrew)
> 2. Asks for your Implexa API key (or reads `$IMPLEXA_API_KEY` from env)
> 3. Writes a launcher script at `~/.claude/implexa-hook.sh`
> 4. Writes config at `~/.claude/implexa.env` (chmod 600 — only readable by you)
> 5. Patches `~/.claude/settings.json` to register user-level hooks
> 6. Runs a smoke test to confirm everything works
> 7. Backs up your existing settings.json (in case you ever want to revert)
>
> **After the script finishes:**
> 1. **Fully quit Claude** (Cmd+Q on Mac — not just close the window)
> 2. Relaunch Claude
> 3. Run `/implexa:record-skill` to test capture
>
> If it worked, the next `end_demonstration` response will show `conversationTurns > 0` and `toolCallsCount > 0` — that's the proof hooks are firing.

## Common questions you might get

**"Why a curl pipe to bash? Isn't that risky?"**
> Fair question. The script lives in our public GitHub repo (`Implexa-Inc/implexa-claude-plugin`). You can review it before running:
> ```bash
> curl -sL https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/install-user-hooks.sh | less
> ```
> Or download it first, inspect, then run:
> ```bash
> curl -O https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/install-user-hooks.sh
> chmod +x install-user-hooks.sh
> ./install-user-hooks.sh
> ```

**"What if I don't have an API key yet?"**
> Get one at https://app.implexa.ai/install — sign up if needed (free, no credit card), then visit the install page. Your key starts with `imp_live_`. The script will prompt you if it's not in your shell env.

**"Will it overwrite my existing hooks?"**
> No. The script is idempotent and only adds Implexa entries — your existing hooks (revenoid, custom, etc.) stay intact. Plus it backs up your settings.json before any change.

**"What if I'm on Windows?"**
> The script is macOS / Linux only right now (relies on bash + Homebrew). For Windows users, we'll ship a PowerShell version later — for now, capture works only on Claude Code CLI on Windows (where plugin hooks fire natively).

## What's next?

```
Run /implexa:record-skill to test that hooks fire correctly.
```

```
Visit app.implexa.ai/skills/<slug>/raw-capture to see what was captured.
```

```
Share your first captured skill — unlock Founding Creator status.
```

## Notes for the model

- **The capture loop has three layers** (Implexa MCP auto-logging + record_demo_note manual fallback + host hooks). Even without hooks, captures work via the first two — but the SKILL.md is less rich. Hooks are the icing.
- **Why user-level over plugin-level:** Cowork's sandbox flag `--setting-sources user` silently drops plugin-packaged hooks. User-level hooks at `~/.claude/settings.json` are honored on every surface.
- **The launcher script is stable.** It resolves the plugin version dynamically (`ls -td ~/.claude/plugins/cache/implexa/implexa/*/`), so plugin updates don't break the wiring.
- **Smoke test simulates GUI env.** The script runs `env -i HOME=... PATH=/usr/bin:/bin bash -c '...'` to reproduce what Claude Desktop sees — catching PATH and env issues before the user hits them at runtime.

## Error handling

| User reports                              | Likely cause                                                          | Tell them                                                                                                            |
|-------------------------------------------|-----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| `curl: command not found`                 | Rare on macOS; curl is built in                                       | "Install curl: `brew install curl`"                                                                                   |
| `brew: command not found`                 | Homebrew not installed                                                | "Install Homebrew first: https://brew.sh — takes 60 seconds"                                                          |
| Script asks for API key but I don't have one | No Implexa account yet                                              | "Sign up at app.implexa.ai/signup (free, no card), then visit app.implexa.ai/install for your key (starts with imp_live_)" |
| After running, conversationTurns is STILL 0 | Didn't fully quit + relaunch Claude                                  | "Cmd+Q the Claude app entirely, then reopen. /reload-plugins isn't enough — settings.json hooks need a fresh session." |
| Permission denied writing settings.json   | Settings file is read-only or in unexpected location                  | "Check: `ls -la ~/.claude/settings.json` — should be writable by your user. If not, `chmod u+w ~/.claude/settings.json` first." |
