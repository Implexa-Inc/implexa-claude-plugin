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
  if command -v brew >/dev/null 2>&1; then
    info "Installing jq via Homebrew..."
    brew install jq
    ok "jq installed"
  else
    err "Homebrew not found. Install jq manually:"
    echo "    https://github.com/jqlang/jq"
    echo "  Or install Homebrew first: https://brew.sh"
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

# ─── 7. Write launcher script ──────────────────────────────────────────
cat > "$LAUNCHER" << 'EOF'
#!/usr/bin/env bash
# Implexa hook launcher.
#
# Stable entry point referenced from ~/.claude/settings.json. Resolves the
# currently-installed plugin version dynamically so it survives plugin
# updates. Sources implexa.env so env vars are available even when Claude
# is launched from Finder (GUI env vs shell env).

# Add Homebrew bin paths — Claude Desktop's GUI process has a minimal PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Source the config file if shell env didn't provide IMPLEXA_API_KEY.
if [ -z "${IMPLEXA_API_KEY:-}" ] && [ -f "$HOME/.claude/implexa.env" ]; then
  set -a
  source "$HOME/.claude/implexa.env"
  set +a
fi

# Find the currently-installed plugin's hook script.
PLUGIN_DIR=$(ls -td "$HOME/.claude/plugins/cache/implexa/implexa/"*/ 2>/dev/null | head -n 1)
if [ -z "$PLUGIN_DIR" ]; then exit 0; fi

# Forward the stdin payload + event to the plugin's hook handler.
exec "$PLUGIN_DIR/hooks/implexa-event.sh"
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
# when PLUGIN_DIR is empty, so without this check the smoke test would
# falsely pass for users who never completed Step 2 of the install.
PLUGIN_DIR=$(ls -td "$HOME/.claude/plugins/cache/implexa/implexa/"*/ 2>/dev/null | head -n 1)
if [ -z "$PLUGIN_DIR" ]; then
  warn "Plugin not found at $HOME/.claude/plugins/cache/implexa/implexa/"
  echo "    The hooks are now installed and will be ready as soon as the plugin is."
  echo "    If you've already installed the Implexa plugin in Claude Desktop"
  echo "    (Customize → Personal plugins → Add marketplace) but still see this,"
  echo "    please report it: https://github.com/Implexa-Inc/implexa-claude-plugin/issues"
  echo ""
  info "Skipping the launcher exec test (no plugin to forward to yet)."
else
  ok "Plugin found at $PLUGIN_DIR"
  SMOKE_PAYLOAD='{"hook_event_name":"UserPromptSubmit","prompt":"installer smoke test","session_id":"installer","transcript_path":"/tmp/nope","cwd":"/tmp"}'
  if env -i HOME="$HOME" PATH="/usr/bin:/bin" \
       bash -c "echo '$SMOKE_PAYLOAD' | '$LAUNCHER'" >/dev/null 2>&1; then
    ok "Smoke test passed — launcher runs cleanly in GUI-like environment"
  else
    err "Smoke test failed."
    echo "Diagnostic info:"
    echo "  - jq location:        $(command -v jq || echo 'NOT FOUND')"
    echo "  - launcher exists:    $([ -x "$LAUNCHER" ] && echo 'yes' || echo 'NO')"
    echo "  - plugin location:    $PLUGIN_DIR"
    echo "  - config exists:      $([ -r "$CONFIG" ] && echo 'yes' || echo 'NO')"
    exit 1
  fi
fi

# ─── 10. Done ───────────────────────────────────────────────────────────
echo ""
echo "${C_BOLD}${C_GREEN}🎉 Setup complete.${C_RESET}"
echo ""
echo "${C_BOLD}Next steps:${C_RESET}"
echo "  1. ${C_BOLD}Fully quit Claude${C_RESET} (Cmd+Q on Mac — not just close the window)"
echo "  2. Relaunch Claude"
echo "  3. Run ${C_BOLD}/implexa:record-skill${C_RESET} to test capture"
echo ""
echo "Verify the capture worked: visit app.implexa.ai/skills/<your-skill-slug>/raw-capture"
echo "If conversationTurns > 0, hooks are firing — the killer feature is live."
echo ""
echo "Settings backup saved at: $BACKUP"
echo "(In case you ever need to restore: cp $BACKUP $SETTINGS)"
echo ""
