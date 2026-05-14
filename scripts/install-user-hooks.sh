#!/usr/bin/env bash
#
# Implexa user-hooks installer
# ──────────────────────────────────────────────────────────────────────────
# Run with:
#   curl -sL https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/install-user-hooks.sh | bash
#
# What it does (one-time setup, idempotent — safe to re-run):
#   1. Verifies jq is installed (installs via Homebrew if missing)
#   2. Reads IMPLEXA_API_KEY from env or prompts you for one
#   3. Writes ~/.claude/implexa-hook.sh   — launcher script with PATH fix
#   4. Writes ~/.claude/implexa.env       — config file (chmod 600)
#   5. Patches ~/.claude/settings.json    — registers user-level hooks
#   6. Runs a smoke test to verify the chain works
#   7. Backs up your previous settings.json
#
# Why user-level hooks (not just plugin hooks)?
#   Claude Desktop / Cowork sandbox plugin-packaged hooks/hooks.json (the
#   --setting-sources user flag). To make UserPromptSubmit + Stop +
#   PostToolUse fire on every surface, the hooks must be at the user level
#   in ~/.claude/settings.json. This script installs them there.
#
# After this script: fully quit Claude (Cmd+Q on Mac) and relaunch.

set -e

CLAUDE_DIR="$HOME/.claude"
LAUNCHER="$CLAUDE_DIR/implexa-hook.sh"
CONFIG="$CLAUDE_DIR/implexa.env"
SETTINGS="$CLAUDE_DIR/settings.json"
BACKUP="$SETTINGS.implexa-backup-$(date +%s)"

# Color helpers — use ANSI-C quoting ($'...') so the variables contain the
# actual ESC character, not the literal string "\033". This makes them work
# correctly with both `echo` and `printf` regardless of shell echo flavor.
if [ -t 1 ]; then
  C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_YELLOW=$'\033[0;33m'; C_BLUE=$'\033[0;34m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''; C_RESET=''
fi

ok()   { printf "%s✓%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf "%s⚠%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "%s✗%s %s\n" "$C_RED"    "$C_RESET" "$*" >&2; }
info() { printf "%s→%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }

# Helper: ensure Homebrew is available; offer to auto-install if missing.
# Returns 0 on success (brew callable), 1 if user declined or install failed.
# Idempotent — safe to call from multiple dependency checks.
ensure_brew() {
  if command -v brew >/dev/null 2>&1; then return 0; fi

  warn "Homebrew is required to install missing dependencies."
  echo "    Homebrew is the standard macOS package manager. It's used to install"
  echo "    Node.js (needed for the Implexa MCP server) and jq if missing."
  echo "    First-time install: ~5 minutes, will prompt for your Mac password."
  echo ""

  if [ ! -r /dev/tty ]; then
    err "No terminal available to prompt. Install Homebrew manually from https://brew.sh"
    return 1
  fi
  echo -n "Install Homebrew now? [Y/n]: "
  local confirm
  read -r confirm < /dev/tty
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    err "Aborted. To install Homebrew manually:"
    echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo "    Then re-run this script."
    return 1
  fi

  info "Installing Homebrew (this will take a few minutes)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty || return 1

  # Add brew to PATH for the rest of this script's execution.
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew installed at $(command -v brew)"
    return 0
  else
    err "Homebrew install ran but brew is not in PATH. Open a new terminal and re-run."
    return 1
  fi
}

echo ""
echo "${C_BOLD}🔧 Implexa user-hooks installer${C_RESET}"
echo ""

# ─── 1. Ensure ~/.claude exists ────────────────────────────────────────
# Both Claude Code CLI and Claude Desktop read user-level config from
# ~/.claude/settings.json, but neither necessarily CREATES the directory
# on first run (Desktop tends to put its own Electron state under
# ~/Library/Application Support/Claude/). Just mkdir -p it — that's the
# whole point of this script.
if [ ! -d "$CLAUDE_DIR" ]; then
  mkdir -p "$CLAUDE_DIR"
  ok "Created Claude config directory at $CLAUDE_DIR"
else
  ok "Claude config directory found at $CLAUDE_DIR"
fi

# ─── 2. Check jq ────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  warn "jq is required but not installed."
  if ensure_brew; then
    info "Installing jq via Homebrew..."
    brew install jq
    ok "jq installed"
  else
    err "Cannot install jq without Homebrew. See message above."
    exit 1
  fi
else
  ok "jq found at $(command -v jq)"
fi

# ─── 3. (was python3 check — removed) ──────────────────────────────────
# We previously checked for python3 here for settings.json patching, but on
# fresh Macs /usr/bin/python3 is a SHIM that exists for `command -v` but
# triggers an Xcode Command Line Tools install dialog on first invocation.
# Switched to jq for the patch step instead (already a hard dependency above).

# ─── 3b. Check Node.js / npx (REQUIRED for MCP server) ─────────────────
# The plugin's MCP server runs via `npx -y @implexa/mcp-server`. Without
# Node.js installed, Cowork/Desktop will spawn the server, fail with
# "command not found: npx", and show "MCP server disconnected" — which
# we discovered the hard way during Sanna's fresh-Mac test.
if ! command -v npx >/dev/null 2>&1; then
  warn "Node.js / npx is required for the Implexa MCP server but not installed."
  if ensure_brew; then
    info "Installing Node.js via Homebrew (~30s)..."
    brew install node
    ok "Node.js installed at $(command -v node)"
  else
    err "Cannot install Node.js without Homebrew."
    echo "    Alternative: download Node.js LTS directly from https://nodejs.org/"
    echo "    Then re-run this script."
    exit 1
  fi
else
  ok "Node.js / npx found at $(command -v npx)"
fi

# ─── 4. Get the API key (env or prompt) ────────────────────────────────
# CRITICAL: when this script is run via `curl ... | bash`, stdin IS the
# script source. A naive `read -r API_KEY` would steal the next line of
# the script itself instead of reading from the keyboard, breaking the
# parse with cryptic syntax errors later. Always read from /dev/tty so
# we get keyboard input regardless of how the script was invoked.
API_KEY="${IMPLEXA_API_KEY:-}"
if [ -z "$API_KEY" ]; then
  if [ ! -r /dev/tty ]; then
    err "No API key provided and no terminal available to prompt."
    err "Either set IMPLEXA_API_KEY first, or download the script and run it directly:"
    echo "    curl -O https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/install-user-hooks.sh"
    echo "    bash install-user-hooks.sh"
    exit 1
  fi
  echo ""
  echo "${C_BOLD}Enter your Implexa API key (imp_live_...):${C_RESET}"
  echo "Get one at https://app.implexa.ai/install"
  echo -n "API key: "
  read -r API_KEY < /dev/tty
  echo ""
  if [ -z "$API_KEY" ]; then
    err "No API key provided. Aborting."
    exit 1
  fi
fi
case "$API_KEY" in
  imp_*) ok "API key looks valid (starts with imp_)" ;;
  *)     warn "API key doesn't start with 'imp_' — proceeding anyway, but double-check it's correct" ;;
esac

# ─── 5. Backup existing settings.json ──────────────────────────────────
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$BACKUP"
  ok "Backed up $SETTINGS → $BACKUP"
else
  echo '{}' > "$SETTINGS"
  ok "Created empty $SETTINGS"
fi

# ─── 6. Write config file (with restrictive permissions) ───────────────
cat > "$CONFIG" << EOF
# Implexa hook config — auto-generated by install-user-hooks.sh
# This file is sourced by ~/.claude/implexa-hook.sh so the hook script
# has access to your API key even when Claude is launched from Finder
# (where shell env vars from ~/.zshrc are NOT inherited).
export IMPLEXA_API_KEY="$API_KEY"
export IMPLEXA_API_URL="https://core.implexa.ai"
EOF
chmod 600 "$CONFIG"
ok "Wrote config: $CONFIG (chmod 600 — only you can read it)"

# ─── 6b. Set launchctl env (helps Claude Code CLI launches) ────────────
# launchctl env reaches any GUI process Launchd spawns thereafter. Useful
# for CLI launches and as a belt-and-suspenders measure. But it does NOT
# reliably reach Claude Desktop/Cowork MCP servers (Anthropic's plugin
# .mcp.json substitution from process env appears unreliable in Cowork).
# We patch claude_desktop_config.json explicitly below for that.
if [[ "$OSTYPE" == "darwin"* ]] && command -v launchctl >/dev/null 2>&1; then
  launchctl setenv IMPLEXA_API_KEY "$API_KEY"
  launchctl setenv IMPLEXA_API_URL "https://core.implexa.ai"
  ok "Set IMPLEXA_API_KEY in launchctl env"
fi

# ─── 6c. Patch claude_desktop_config.json (Desktop / Cowork MCP wiring) ─
# Plugin's .mcp.json declares the implexa MCP server with ${IMPLEXA_API_KEY}
# substitution, but Anthropic's Cowork doesn't appear to substitute reliably
# from launchctl env. The reliable path is to register the MCP server in
# claude_desktop_config.json with HARDCODED env values — same pattern
# Anthropic's own examples use (and that revenoid-local does).
#
# We preserve all other top-level keys (preferences, other mcpServers, etc).
DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
DESKTOP_CFG_DIR="$(dirname "$DESKTOP_CFG")"
if [ -d "$DESKTOP_CFG_DIR" ]; then
  # Ensure the file exists with at least an empty object
  if [ ! -f "$DESKTOP_CFG" ]; then
    echo '{}' > "$DESKTOP_CFG"
  else
    # Back up — same convention as settings.json
    cp "$DESKTOP_CFG" "$DESKTOP_CFG.implexa-backup-$(date +%s)"
  fi

  DESKTOP_TMP="$DESKTOP_CFG.tmp.$$"
  if ! jq --arg key "$API_KEY" --arg url "https://core.implexa.ai" '
    .mcpServers = (.mcpServers // {})
    | .mcpServers.implexa = {
        command: "npx",
        args: ["-y", "@implexa/mcp-server"],
        env: {
          IMPLEXA_API_KEY: $key,
          IMPLEXA_API_URL: $url
        }
      }
  ' "$DESKTOP_CFG" > "$DESKTOP_TMP"; then
    err "Failed to patch $DESKTOP_CFG. Original unchanged."
    rm -f "$DESKTOP_TMP"
  else
    mv "$DESKTOP_TMP" "$DESKTOP_CFG"
    ok "Registered implexa MCP server in claude_desktop_config.json"
  fi
else
  warn "Claude Desktop config directory not found: $DESKTOP_CFG_DIR"
  echo "    (skipping Desktop/Cowork MCP wiring — only matters if you use Desktop or Cowork)"
fi

# ─── 7. Write launcher script ──────────────────────────────────────────
cat > "$LAUNCHER" << 'EOF'
#!/usr/bin/env bash
# Implexa hook launcher.
#
# Stable entry point referenced from ~/.claude/settings.json. Resolves the
# plugin's hook handler dynamically so it survives plugin updates. Sources
# implexa.env so env vars are available even when Claude is launched from
# Finder (GUI env vs shell env).
#
# Two plugin install locations exist — Claude Code CLI uses ~/.claude/...
# while Claude Desktop uses ~/Library/Application Support/Claude/local-
# agent-mode-sessions/*/*/rpm/plugin_*/ (different per session, opaque
# IDs). We search both, preferring whichever has a newer mtime.

# Add Homebrew bin paths — Claude Desktop's GUI process has a minimal PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Source the config file if shell env didn't provide IMPLEXA_API_KEY.
if [ -z "${IMPLEXA_API_KEY:-}" ] && [ -f "$HOME/.claude/implexa.env" ]; then
  set -a
  source "$HOME/.claude/implexa.env"
  set +a
fi

# Find the plugin's hook handler. Both globs are silently empty when their
# install location doesn't exist. ls -t sorts by mtime descending — most
# recent install wins.
PLUGIN_HOOK=$(
  {
    ls -t "$HOME/.claude/plugins/cache/implexa/implexa/"*/hooks/implexa-event.sh 2>/dev/null
    ls -t "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/"*/*/rpm/plugin_*/hooks/implexa-event.sh 2>/dev/null
  } | head -n 1
)
if [ -z "$PLUGIN_HOOK" ] || [ ! -x "$PLUGIN_HOOK" ]; then exit 0; fi

# Forward the stdin payload + event to the plugin's hook handler.
exec "$PLUGIN_HOOK"
EOF
chmod +x "$LAUNCHER"
ok "Wrote launcher: $LAUNCHER"

# ─── 8. Patch settings.json (idempotent) ───────────────────────────────
# Uses jq instead of python3 — fresh Macs lack working python3 (the
# /usr/bin/python3 shim triggers an Xcode CLT install dialog instead of
# running), so we'd block on a 5–10 minute compiler-tools install for a
# trivial JSON edit. jq is already a hard dep above.
#
# Logic: for each of the 3 hook events, ensure .hooks[event] is an array
# containing a matcher="*" group, and that group's hooks contain our
# launcher command. All operations are idempotent on the second run.
LAUNCHER_CMD='$HOME/.claude/implexa-hook.sh'
TMP_SETTINGS="$SETTINGS.tmp.$$"
if ! jq --arg cmd "$LAUNCHER_CMD" '
  .hooks = (.hooks // {})
  | reduce ["UserPromptSubmit", "Stop", "PostToolUse"][] as $event (.;
      .hooks[$event] = (.hooks[$event] // [])
      | (if (.hooks[$event] | any(.matcher == "*" or .matcher == "")) then .
         else .hooks[$event] += [{matcher: "*", hooks: []}]
         end)
      | .hooks[$event] |= map(
          if (.matcher == "*" or .matcher == "") then
            .hooks = (.hooks // [])
            | (if (.hooks | any(.command == $cmd)) then .
               else .hooks += [{type: "command", command: $cmd}]
               end)
          else .
          end
        )
    )
' "$SETTINGS" > "$TMP_SETTINGS"; then
  err "Failed to patch $SETTINGS via jq. Original is unchanged."
  rm -f "$TMP_SETTINGS"
  exit 1
fi
mv "$TMP_SETTINGS" "$SETTINGS"
ok "settings.json patched (3 hook events registered)"

# ─── 9. Smoke test ─────────────────────────────────────────────────────
echo ""
info "Running smoke test (simulates Claude Desktop's clean GUI environment)..."

# First — check the plugin is actually findable. The launcher silently exits 0
# when its glob is empty, so without this check the smoke test would falsely
# pass for users who never completed Step 2 of the install.
#
# Two install locations: CLI (~/.claude/plugins/cache/...) and Desktop
# (~/Library/Application Support/Claude/local-agent-mode-sessions/...).
PLUGIN_HOOK=$(
  {
    ls -t "$HOME/.claude/plugins/cache/implexa/implexa/"*/hooks/implexa-event.sh 2>/dev/null
    ls -t "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/"*/*/rpm/plugin_*/hooks/implexa-event.sh 2>/dev/null
  } | head -n 1
)
if [ -z "$PLUGIN_HOOK" ]; then
  warn "Implexa plugin not found in either install location:"
  echo "    - $HOME/.claude/plugins/cache/implexa/implexa/  (Claude Code CLI)"
  echo "    - $HOME/Library/Application Support/Claude/local-agent-mode-sessions/.../rpm/plugin_.../  (Claude Desktop)"
  echo ""
  echo "    The user-level hooks are now installed and will activate as soon as the plugin is."
  echo "    If you've already installed the Implexa plugin in Claude Desktop"
  echo "    (Customize → Personal plugins → Add marketplace → Install) but still see this,"
  echo "    please report it: https://github.com/Implexa-Inc/implexa-claude-plugin/issues"
  echo ""
  info "Skipping the launcher exec test (no plugin to forward to yet)."
else
  ok "Plugin found at $PLUGIN_HOOK"
  SMOKE_PAYLOAD='{"hook_event_name":"UserPromptSubmit","prompt":"installer smoke test","session_id":"installer","transcript_path":"/tmp/nope","cwd":"/tmp"}'
  if env -i HOME="$HOME" PATH="/usr/bin:/bin" \
       bash -c "echo '$SMOKE_PAYLOAD' | '$LAUNCHER'" >/dev/null 2>&1; then
    ok "Smoke test passed — launcher runs cleanly in GUI-like environment"
  else
    err "Smoke test failed."
    echo "Diagnostic info:"
    echo "  - jq location:        $(command -v jq || echo 'NOT FOUND')"
    echo "  - launcher exists:    $([ -x "$LAUNCHER" ] && echo 'yes' || echo 'NO')"
    echo "  - plugin location:    $PLUGIN_HOOK"
    echo "  - config exists:      $([ -r "$CONFIG" ] && echo 'yes' || echo 'NO')"
    exit 1
  fi
fi

# ─── 10. Done ───────────────────────────────────────────────────────────
echo ""
echo "${C_BOLD}${C_GREEN}🎉 Setup complete.${C_RESET}"
echo ""
echo "${C_BOLD}Next steps:${C_RESET}"
echo "  1. ${C_BOLD}Fully quit Claude${C_RESET} (Cmd+Q on Mac — closing windows isn't enough)"
echo "     This is REQUIRED — MCP servers + env vars are read on launch."
echo "  2. ${C_BOLD}(If plugin updated)${C_RESET} reinstall the plugin: Customize → Personal plugins"
echo "     → Implexa → remove, then re-add via the marketplace. This pulls"
echo "     the latest skill text (slash command prompts updated)."
echo "  3. Relaunch Claude (Desktop, Cowork, or CLI)"
echo "  4. Run ${C_BOLD}/implexa:setup${C_RESET} to verify MCP connected"
echo "     You should see: ✅ You're connected to Implexa"
echo "  5. Run ${C_BOLD}/implexa:record-skill${C_RESET} to test capture"
echo ""
echo "Verify the capture worked: visit app.implexa.ai/skills/<your-skill-slug>/raw-capture"
echo "Both signals should be non-zero:"
echo "  - toolCallsCount > 0           (PostToolUse hook fired)"
echo "  - conversationTurns >= 2       (UserPromptSubmit + Stop hooks fired)"
echo ""
echo "Settings backup saved at: $BACKUP"
echo "(In case you ever need to restore: cp $BACKUP $SETTINGS)"
echo ""
