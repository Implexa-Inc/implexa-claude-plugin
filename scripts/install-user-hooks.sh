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

# If Homebrew is installed but not on PATH (common right after first install
# before the user has restarted their shell), proactively add it. Otherwise
# subsequent `command -v npx` etc. checks falsely report things as missing.
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

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

  # Brew might already be installed but not in PATH (very common after a
  # first install — the Homebrew installer prints instructions for adding
  # to .zprofile but doesn't apply them to the current shell). Check the
  # two standard install locations and add to PATH if found.
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    if command -v brew >/dev/null 2>&1; then
      ok "Homebrew found at /opt/homebrew/bin/brew (added to PATH for this run)"
      return 0
    fi
  fi
  if [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
    if command -v brew >/dev/null 2>&1; then
      ok "Homebrew found at /usr/local/bin/brew (added to PATH for this run)"
      return 0
    fi
  fi

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
    # </dev/null is CRITICAL — `brew install` slurps stdin and would
    # consume the rest of our script (stdin = curl pipe under `curl|bash`).
    brew install jq </dev/null
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
    # </dev/null is CRITICAL — `brew install` slurps stdin and would
    # consume the rest of our script (stdin = curl pipe under `curl|bash`).
    # Without this, the script terminates silently after Node.js install
    # because bash runs out of script to read.
    brew install node </dev/null
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

# ─── 4. Get the API key (token, env, device-auth, or prompt) ───────────
# Resolution order (in priority):
#   1. IMPLEXA_API_KEY env var — explicit override (CI, advanced users)
#   2. IMPLEXA_INSTALL_TOKEN — short-lived token redeemed for a fresh API
#      key (set by core.implexa.ai/install.sh when user copies the pre-
#      baked curl from app.implexa.ai/install)
#   3. Device-auth flow — opens the user's browser to log in / sign up,
#      polls for approval, mints a fresh API key on success. This is the
#      default path for the universal `curl install.sh | bash` command
#      that the marketing site shows. RFC 8628 device-authorization grant.
#   4. Interactive prompt for raw API key — last-resort fallback when
#      no browser is available (SSH, headless CI)
#
# CRITICAL: when this script is run via `curl ... | bash`, stdin IS the
# script source. A naive `read -r API_KEY` would steal the next line of
# the script itself instead of reading from the keyboard, breaking the
# parse with cryptic syntax errors later. Always read from /dev/tty so
# we get keyboard input regardless of how the script was invoked.
API_KEY="${IMPLEXA_API_KEY:-}"
API_BASE="${IMPLEXA_API_BASE_URL:-https://core.implexa.ai}"

# Try to open a URL in the user's default browser. Best-effort on macOS
# (open), Linux (xdg-open), and Windows WSL (wslview / cmd.exe). Silent
# on failure — the URL is also printed so the user can copy/paste.
open_browser() {
  local url="$1"
  if   command -v open       >/dev/null 2>&1; then open "$url"     >/dev/null 2>&1 &
  elif command -v xdg-open   >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
  elif command -v wslview    >/dev/null 2>&1; then wslview "$url"  >/dev/null 2>&1 &
  fi
}

# ── Path 1: Install token (pre-baked from dashboard /install) ─────────
if [ -z "$API_KEY" ] && [ -n "${IMPLEXA_INSTALL_TOKEN:-}" ]; then
  echo "→ Redeeming install token..."
  REDEEM_RESPONSE=$(curl -sS -X POST "$API_BASE/api/v2/install-tokens/$IMPLEXA_INSTALL_TOKEN/redeem" \
    -H "Content-Type: application/json" 2>&1 || echo '{"error":"network error"}')
  API_KEY=$(echo "$REDEEM_RESPONSE" | jq -r '.apiKey // empty' 2>/dev/null)
  REDEEM_ERROR=$(echo "$REDEEM_RESPONSE" | jq -r '.error // empty' 2>/dev/null)
  if [ -z "$API_KEY" ]; then
    err "Failed to redeem install token: ${REDEEM_ERROR:-unknown error}"
    err "Tokens expire after 10 min and are single-use."
    err "Get a fresh install command at https://app.implexa.ai/install"
    exit 1
  fi
  ok "Token redeemed — got a fresh API key (${API_KEY:0:13}...)"
fi

# ── Path 2: Device-auth flow (browser login from terminal) ───────────
# Used when the user runs the universal install command:
#   curl -fsSL https://core.implexa.ai/install.sh | bash
# No token, no env key — we kick off RFC 8628 device authorization:
# print a URL + verification code, open the browser, poll for approval.
if [ -z "$API_KEY" ] && [ -r /dev/tty ]; then
  echo ""
  info "Starting browser login..."
  START_RESPONSE=$(curl -sS -X POST "$API_BASE/api/v2/cli-auth/start" \
    -H "Content-Type: application/json" -d '{}' 2>&1 || echo '{"error":"network error"}')
  DEVICE_CODE=$(echo "$START_RESPONSE"   | jq -r '.deviceCode // empty'       2>/dev/null)
  VERIFICATION_CODE=$(echo "$START_RESPONSE" | jq -r '.verificationCode // empty' 2>/dev/null)
  VERIFICATION_URL=$(echo "$START_RESPONSE"  | jq -r '.verificationUrl // empty'  2>/dev/null)
  POLL_INTERVAL=$(echo "$START_RESPONSE" | jq -r '.interval // 2'              2>/dev/null)
  EXPIRES_IN=$(echo "$START_RESPONSE"    | jq -r '.expiresIn // 600'           2>/dev/null)

  if [ -z "$DEVICE_CODE" ] || [ -z "$VERIFICATION_URL" ]; then
    err "Failed to start browser login (could not reach $API_BASE)."
    err "Falling back to manual API-key prompt."
  else
    echo ""
    echo "${C_BOLD}Open this URL in your browser to log in:${C_RESET}"
    echo ""
    echo "    ${C_BLUE}$VERIFICATION_URL${C_RESET}"
    echo ""
    echo "${C_BOLD}Verification code:${C_RESET}  ${C_GREEN}$VERIFICATION_CODE${C_RESET}"
    echo "    Make sure the browser shows the same code before approving."
    echo ""

    open_browser "$VERIFICATION_URL"
    info "Tried to open your browser automatically. If nothing happened, copy the URL above."

    # Poll loop. POLL_INTERVAL is seconds (server says 2). Cap total wait
    # at EXPIRES_IN seconds, with a small buffer so we time out gracefully.
    MAX_POLLS=$(( (EXPIRES_IN / POLL_INTERVAL) + 5 ))
    POLL_COUNT=0
    AUTH_EMAIL=""
    echo -n "→ Waiting for approval (press Ctrl+C to cancel) "
    while [ $POLL_COUNT -lt $MAX_POLLS ]; do
      sleep "$POLL_INTERVAL"
      POLL_RESPONSE=$(curl -sS -X POST "$API_BASE/api/v2/cli-auth/poll" \
        -H "Content-Type: application/json" \
        -d "{\"deviceCode\":\"$DEVICE_CODE\"}" 2>&1 || echo '{"status":"network-error"}')
      POLL_STATUS=$(echo "$POLL_RESPONSE" | jq -r '.status // empty' 2>/dev/null)

      case "$POLL_STATUS" in
        approved)
          API_KEY=$(echo "$POLL_RESPONSE"    | jq -r '.apiKey // empty' 2>/dev/null)
          AUTH_EMAIL=$(echo "$POLL_RESPONSE" | jq -r '.email // empty'  2>/dev/null)
          if [ -n "$API_KEY" ]; then
            echo ""
            ok "Logged in as ${C_BOLD}$AUTH_EMAIL${C_RESET}"
          fi
          break
          ;;
        denied)
          echo ""
          err "You denied this login request. Run the install command again if that wasn't intentional."
          exit 1
          ;;
        expired)
          echo ""
          err "Login session expired (${EXPIRES_IN}s timeout). Run the install command again."
          exit 1
          ;;
        consumed)
          echo ""
          err "Login session already used. Run the install command again to start fresh."
          exit 1
          ;;
        pending|"")
          # Still waiting — print a dot every ~5 polls so the line isn't silent.
          if [ $(( POLL_COUNT % 5 )) -eq 0 ]; then printf "."; fi
          ;;
        *)
          # Unknown status (network error, server bug). Keep polling — server
          # might recover; if not, MAX_POLLS will time us out.
          if [ $(( POLL_COUNT % 5 )) -eq 0 ]; then printf "?"; fi
          ;;
      esac
      POLL_COUNT=$(( POLL_COUNT + 1 ))
    done

    if [ -z "$API_KEY" ]; then
      echo ""
      err "Timed out waiting for browser approval. Run the install command again."
      exit 1
    fi

    # ── Confirmation gate — matches `stripe login` / `gh auth login` UX ──
    # User just logged in via the browser; now we make sure they're ready
    # before we touch their machine. Press Enter to proceed.
    echo ""
    echo "${C_BOLD}Press Enter to install, or Ctrl+C to cancel.${C_RESET}"
    read -r _confirm < /dev/tty || true
  fi
fi

# ── Path 3: Last-resort manual API-key prompt ─────────────────────────
# Only hit when device-auth couldn't run (no tty, network error during
# /cli-auth/start, etc.). Same behavior as the original install script.
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

# Source implexa.env unconditionally so debug flags / API URL / etc.
# propagate even when IMPLEXA_API_KEY is already in the GUI process env
# (set via launchctl). Save the pre-existing key first so a shell-set
# value takes precedence — important for CLI users who export it in
# their .zshrc with a different/newer value than what's in the file.
if [ -f "$HOME/.claude/implexa.env" ]; then
  _saved_key="${IMPLEXA_API_KEY:-}"
  set -a
  source "$HOME/.claude/implexa.env"
  set +a
  if [ -n "$_saved_key" ]; then
    export IMPLEXA_API_KEY="$_saved_key"
  fi
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

# ─── 8b. Bump MCP_TOOL_TIMEOUT in settings.json (idempotent) ───────────
# Implexa's finalize step (Anthropic Haiku writes a 6000-8000 token SKILL.md
# after a recording wraps) routinely takes 30-90s for rich skills. Claude
# Code's bundled MCP SDK caps tool calls at the default 60000ms, which
# surfaces as "MCP error -32001: Request timeout" — purely cosmetic
# (the skill IS saved server-side), but it looks scary to the user.
#
# MCP_TOOL_TIMEOUT (read by Claude Code, NOT the spawned server) is the
# only documented knob. There is no per-server timeout in .mcp.json: see
# anthropics/claude-code#43791 + #22542 — a "timeout" sibling of
# command/args/env is silently ignored. The fix has to live in the user's
# ~/.claude/settings.json env block.
#
# v0.10.1 raises this to 300000ms (5 min). v0.6.1 originally raised to
# 180000ms (3 min) based on the observed 90s ceiling for normal save flows.
# In practice the re-record-into-existing-skill merge (Haiku rewrites a
# 200+ line skill and reconciles a 50+ call new trace into one updated
# SKILL.md) routinely hits 180-250s. 300s gives margin without making
# genuinely-hung calls invisible. Never downgrades a user-set higher value.
TIMEOUT_TARGET=300000
TMP_SETTINGS2="$SETTINGS.tmp2.$$"
if ! jq --argjson target "$TIMEOUT_TARGET" '
  .env = (.env // {})
  | .env.MCP_TOOL_TIMEOUT = (
      if ((.env.MCP_TOOL_TIMEOUT // "0") | tonumber? // 0) >= $target
        then .env.MCP_TOOL_TIMEOUT
        else ($target | tostring)
      end
    )
' "$SETTINGS" > "$TMP_SETTINGS2"; then
  warn "Could not patch MCP_TOOL_TIMEOUT in $SETTINGS (hooks patch from previous step is intact)."
  rm -f "$TMP_SETTINGS2"
else
  mv "$TMP_SETTINGS2" "$SETTINGS"
  ok "settings.json env.MCP_TOOL_TIMEOUT set to ${TIMEOUT_TARGET}ms (avoids cosmetic -32001 during skill authoring)"
fi

# ─── 8d. Ambient recommender hook (P2): opt-in consent ────────────────
# Implexa watches every UserPromptSubmit and surfaces ONE skill suggestion
# when the prompt semantically matches an aggregated skill above threshold.
#
# Privacy promise (made source-of-truth in the backend):
#   * Prompts that match a skill → retained for ranking improvement.
#   * Prompts that do NOT match  → discarded, never logged.
#
# Failure here is NON-FATAL. The existing user-level hooks for demo
# recording (step 8a) work without the recommender. If the user declines
# or this step fails, the rest of the install proceeds normally.

RECOMMEND_LAUNCHER="$CLAUDE_DIR/implexa-recommend.sh"
RECOMMEND_LAUNCHER_CMD='$HOME/.claude/implexa-recommend.sh'

install_recommender_hook() {
  # ── Consent gate ───────────────────────────────────────────────────
  # The ambient recommender is observably different from the demo hook
  # (it prints inline suggestions). Users who didn't ask for that surface
  # shouldn't get it silently. Block on Enter to opt in.
  echo ""
  echo "${C_BOLD}🪄  ambient skill recommender (optional)${C_RESET}"
  echo ""
  echo "implexa can also watch your sessions and recommend skills as you work."
  echo "one skill, mid-prompt, when something in the implexa index matches."
  echo ""
  echo "${C_BOLD}privacy promise:${C_RESET}"
  echo "  • prompts that produce a recommendation: retained for ranking improvement"
  echo "  • prompts that don't match a skill: discarded, never logged"
  echo ""
  echo "to disable later:"
  echo "  • per-session: type \"mute implexa for this session\""
  echo "  • permanently: remove the implexa-recommend block from ~/.claude/settings.json"
  echo ""

  # Non-interactive run (CI, headless): skip the ambient surface. Users
  # who automate installs probably don't want inline suggestions surfacing
  # to their pipelines. They can always re-run interactively.
  if [ ! -r /dev/tty ]; then
    warn "No terminal available, skipping ambient recommender setup. Re-run interactively to enable."
    return 1
  fi

  echo -n "press ${C_BOLD}enter${C_RESET} to enable, or ${C_BOLD}ctrl-c${C_RESET} to skip: "
  # Read a single line. User may just hit enter (default = enable). If
  # they ctrl-c, the shell trap will fire and `read` returns non-zero.
  if ! read -r _consent < /dev/tty; then
    warn "Skipped ambient recommender (no input received)."
    return 1
  fi
  ok "Consent recorded. Installing ambient recommender hook."

  # ── Write the launcher script ──────────────────────────────────────
  # Same pattern as ~/.claude/implexa-hook.sh: resolve the plugin's hook
  # handler dynamically so plugin updates don't break this entry point.
  cat > "$RECOMMEND_LAUNCHER" << 'RECLAUNCHER'
#!/usr/bin/env bash
# Implexa ambient recommender launcher.
#
# Stable entry point referenced from ~/.claude/settings.json. Resolves the
# plugin's recommend-on-prompt.sh dynamically across CLI / Desktop install
# locations. Sources implexa.env so the API key is in scope even when
# Claude is launched from Finder (no shell env inherited).

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if [ -f "$HOME/.claude/implexa.env" ]; then
  _saved_key="${IMPLEXA_API_KEY:-}"
  set -a
  source "$HOME/.claude/implexa.env"
  set +a
  if [ -n "$_saved_key" ]; then
    export IMPLEXA_API_KEY="$_saved_key"
  fi
fi

PLUGIN_HOOK=$(
  {
    ls -t "$HOME/.claude/plugins/cache/implexa/implexa/"*/hooks/recommend-on-prompt.sh 2>/dev/null
    ls -t "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/"*/*/rpm/plugin_*/hooks/recommend-on-prompt.sh 2>/dev/null
  } | head -n 1
)
if [ -z "$PLUGIN_HOOK" ] || [ ! -x "$PLUGIN_HOOK" ]; then exit 0; fi

exec "$PLUGIN_HOOK"
RECLAUNCHER
  chmod +x "$RECOMMEND_LAUNCHER"
  ok "Wrote ambient recommender launcher: $RECOMMEND_LAUNCHER"

  # ── Patch settings.json: add the recommender command to UserPromptSubmit ──
  # Adds a SECOND command alongside the existing implexa-hook.sh under the
  # same matcher="*" group. Idempotent: re-running the script does NOT
  # double-register.
  local tmp="$SETTINGS.tmp.rec.$$"
  if ! jq --arg cmd "$RECOMMEND_LAUNCHER_CMD" '
    .hooks = (.hooks // {})
    | .hooks.UserPromptSubmit = (.hooks.UserPromptSubmit // [])
    | (if (.hooks.UserPromptSubmit | any(.matcher == "*" or .matcher == "")) then .
       else .hooks.UserPromptSubmit += [{matcher: "*", hooks: []}]
       end)
    | .hooks.UserPromptSubmit |= map(
        if (.matcher == "*" or .matcher == "") then
          .hooks = (.hooks // [])
          | (if (.hooks | any(.command == $cmd)) then .
             else .hooks += [{type: "command", command: $cmd}]
             end)
        else .
        end
      )
  ' "$SETTINGS" > "$tmp"; then
    err "Failed to patch settings.json for ambient recommender. Original is unchanged."
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$SETTINGS"
  ok "settings.json patched (ambient recommender registered under UserPromptSubmit)"

  # Ensure the state dir + an initial state file exist so the first hook
  # invocation doesn't race on dir creation.
  mkdir -p "$HOME/.claude/plugins/implexa" 2>/dev/null || true
  return 0
}

install_recommender_hook || warn "Ambient recommender not installed (the rest of the install is fine)."

# ─── 8e. SkillRank phase A — data-collection consent ───────────────────
# Implexa's recommender gets dramatically better with three signals on
# top of semantic match (tool stack overlap, work-signature similarity,
# outcome attribution). Two of those are low-sensitivity and default on.
# One — work signature for cohort matching — is more sensitive and
# defaults OFF unless the user explicitly opts in.
#
# What gets written:
#   1. ~/.claude/plugins/implexa/consent.json — the hook reads this on
#      every prompt to decide what to send.
#   2. POST /api/v2/mcp record_consent — the backend mirror, source of
#      truth for record_work_signature's gate.
#
# Defaults at install time:
#   tool_inventory_optin   = true   (low sensitivity)
#   outcome_tracking_optin = true   (needed for ranking improvements)
#   work_signature_optin   = false  (strict opt-in for cohort matching)
#
# DO NOT reverse these defaults. The asymmetric framing is the privacy
# positioning ("google sells your data. implexa USES your data, only
# with permission, and only to make YOUR recommendations better").
#
# Non-interactive (curl|bash with no tty): write defaults silently and
# move on. The user can flip flags any time via app.implexa.ai/settings/data.

CONSENT_PATH="$HOME/.claude/plugins/implexa/consent.json"

write_consent_file() {
  # Args: $1=tool_inventory, $2=outcome_tracking, $3=work_signature  (all 'true'|'false')
  mkdir -p "$(dirname "$CONSENT_PATH")" 2>/dev/null || true
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n \
    --argjson tool      "$1" \
    --argjson outcome   "$2" \
    --argjson signature "$3" \
    --arg     ts        "$now" \
    '{
      tool_inventory_optin:   $tool,
      outcome_tracking_optin: $outcome,
      work_signature_optin:   $signature,
      recorded_at:            $ts
    }' > "$CONSENT_PATH" 2>/dev/null
  chmod 600 "$CONSENT_PATH" 2>/dev/null || true
}

post_consent_to_backend() {
  # Args same as write_consent_file. Best-effort, never blocks the install.
  local tool="$1" outcome="$2" signature="$3"
  local body
  body=$(jq -n \
    --argjson tool      "$tool" \
    --argjson outcome   "$outcome" \
    --argjson signature "$signature" \
    '{
      jsonrpc: "2.0",
      id: "implexa-install-consent",
      method: "tools/call",
      params: {
        name: "record_consent",
        arguments: {
          tool_inventory_optin:   $tool,
          outcome_tracking_optin: $outcome,
          work_signature_optin:   $signature
        }
      }
    }' 2>/dev/null) || return 0

  curl --silent --max-time 5 \
    -X POST "${API_BASE}/api/v2/mcp" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$body" >/dev/null 2>&1 || true
}

# Prompt one yes/no. Args: $1=question text, $2='Y'|'N' default
ask_yn() {
  local prompt="$1" default="$2" reply
  local hint="[Y/n]"
  [ "$default" = "N" ] && hint="[y/N]"
  printf '%s %s: ' "$prompt" "$hint"
  if ! read -r reply < /dev/tty; then reply=""; fi
  reply=$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  if [ -z "$reply" ]; then
    [ "$default" = "Y" ] && echo "true" || echo "false"
    return 0
  fi
  case "$reply" in
    y|yes|true|1)  echo "true"  ;;
    *)              echo "false" ;;
  esac
}

run_consent_flow() {
  echo ""
  echo "${C_BOLD}🧠 SkillRank data preferences${C_RESET}"
  echo ""
  echo "implexa learns from how you work to make recommendations better over time."
  echo "this is optional. you can change these any time at app.implexa.ai/settings/data."
  echo ""
  echo "${C_BOLD}defaults${C_RESET} (low-sensitivity, default on):"
  echo "  ✓ track installed tools                — helps recommend skills you can actually run"
  echo "  ✓ track skill outcomes                  — did the recommended skill solve your task"
  echo ""
  echo "${C_BOLD}cohort matching${C_RESET} (more sensitive, default OFF):"
  echo "  ☐ enable cohort matching                — anonymized work signature shared across users"
  echo "    your recommendations get 3x better, but only with your explicit yes"
  echo ""

  # Non-interactive (curl|bash without a tty): write defaults silently.
  if [ ! -r /dev/tty ]; then
    write_consent_file "true" "true" "false"
    post_consent_to_backend "true" "true" "false"
    ok "Wrote defaults to $CONSENT_PATH (tool inventory on, outcome on, cohort matching off)"
    return 0
  fi

  echo -n "press ${C_BOLD}enter${C_RESET} to accept defaults, or type ${C_BOLD}c${C_RESET} to customize: "
  local choice
  if ! read -r choice < /dev/tty; then choice=""; fi
  choice=$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

  local tool="true" outcome="true" signature="false"
  if [ "$choice" = "c" ]; then
    echo ""
    tool=$(ask_yn      "  track installed tools? " "Y")
    outcome=$(ask_yn   "  track skill outcomes?  " "Y")
    signature=$(ask_yn "  enable cohort matching?" "N")
  fi

  write_consent_file "$tool" "$outcome" "$signature"
  post_consent_to_backend "$tool" "$outcome" "$signature"
  ok "Saved preferences (cohort matching: $([ "$signature" = "true" ] && echo on || echo off))"
}

run_consent_flow || warn "Consent flow skipped (the rest of the install is fine; defaults take effect)."

# ─── 8c. Auto-install the Implexa plugin (Claude Code CLI) ─────────────
# Mimics what /plugin marketplace add + /plugin install do internally, so
# users don't have to type those two commands inside Claude Code. After
# this, the user pastes one curl and is fully connected.
#
# What we replicate (Claude Code's plugin install writes these):
#   1. Clone the plugin repo to ~/.claude/plugins/marketplaces/implexa/
#   2. Copy that to ~/.claude/plugins/cache/implexa/implexa/<version>/
#   3. Add an entry to ~/.claude/plugins/known_marketplaces.json
#   4. Add an entry to ~/.claude/plugins/installed_plugins.json
#
# Failure here is NON-FATAL — we fall back to printing the two slash
# commands so the user can run them inside Claude Code manually. Anthropic
# could change this internal format in future versions, and that fallback
# is our safety net.
#
# Note: Claude Code reads these files on launch. If Claude Code is already
# running, the user has to fully quit and relaunch to load the plugin.
# That's already covered by the existing "Next steps" guidance below.

PLUGINS_DIR="$CLAUDE_DIR/plugins"
MARKETPLACES_DIR="$PLUGINS_DIR/marketplaces"
MARKETPLACE_PATH="$MARKETPLACES_DIR/implexa"
CACHE_BASE="$PLUGINS_DIR/cache/implexa/implexa"
KNOWN_MARKETPLACES="$PLUGINS_DIR/known_marketplaces.json"
INSTALLED_PLUGINS="$PLUGINS_DIR/installed_plugins.json"
PLUGIN_REPO_URL="https://github.com/Implexa-Inc/implexa-claude-plugin.git"

print_plugin_fallback() {
  warn "Couldn't auto-install the Implexa plugin into Claude Code."
  echo "    Run these two commands inside Claude Code instead:"
  echo "      /plugin marketplace add Implexa-Inc/implexa-claude-plugin"
  echo "      /plugin install implexa@Implexa-Inc/implexa-claude-plugin"
  echo ""
}

install_implexa_plugin() {
  command -v git >/dev/null 2>&1 || { warn "git not found — can't auto-install plugin"; return 1; }
  mkdir -p "$MARKETPLACES_DIR" "$PLUGINS_DIR/cache/implexa" || return 1

  # ── 1. Clone or refresh the marketplace repo ──
  if [ -d "$MARKETPLACE_PATH/.git" ]; then
    info "Updating Implexa plugin marketplace..."
    if ! (cd "$MARKETPLACE_PATH" && git fetch --quiet origin main && git reset --hard --quiet origin/main); then
      warn "git refresh failed in $MARKETPLACE_PATH (keeping existing copy)"
    fi
  else
    info "Cloning Implexa plugin marketplace..."
    if ! git clone --quiet --depth 1 "$PLUGIN_REPO_URL" "$MARKETPLACE_PATH"; then
      err "git clone failed (network issue?)"
      return 1
    fi
  fi

  # ── 2. Read version + commit sha from the cloned manifest ──
  local plugin_json="$MARKETPLACE_PATH/.claude-plugin/plugin.json"
  if [ ! -f "$plugin_json" ]; then
    err "plugin.json missing after clone: $plugin_json"
    return 1
  fi
  local version commit_sha now
  version=$(jq -r '.version // "unknown"' "$plugin_json")
  commit_sha=$(cd "$MARKETPLACE_PATH" && git rev-parse HEAD 2>/dev/null || echo "unknown")
  # ISO 8601 with millisecond precision on Linux, second precision on BSD/macOS.
  now=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

  # ── 3. Copy marketplace into the versioned cache path ──
  local cache_path="$CACHE_BASE/$version"
  mkdir -p "$CACHE_BASE"
  rm -rf "$cache_path"
  if ! cp -R "$MARKETPLACE_PATH" "$cache_path"; then
    err "Failed to copy plugin to $cache_path"
    return 1
  fi

  # ── 4. Patch known_marketplaces.json ──
  [ -f "$KNOWN_MARKETPLACES" ] || echo '{}' > "$KNOWN_MARKETPLACES"
  local tmp_km="$KNOWN_MARKETPLACES.tmp.$$"
  if ! jq --arg loc "$MARKETPLACE_PATH" --arg now "$now" --arg url "$PLUGIN_REPO_URL" '
    .implexa = {
      source: { source: "git", url: $url },
      installLocation: $loc,
      lastUpdated: $now,
      autoUpdate: true
    }
  ' "$KNOWN_MARKETPLACES" > "$tmp_km"; then
    rm -f "$tmp_km"
    err "Failed to patch known_marketplaces.json"
    return 1
  fi
  mv "$tmp_km" "$KNOWN_MARKETPLACES"

  # ── 5. Patch installed_plugins.json (preserves first-install timestamp) ──
  [ -f "$INSTALLED_PLUGINS" ] || echo '{"version":2,"plugins":{}}' > "$INSTALLED_PLUGINS"
  local tmp_ip="$INSTALLED_PLUGINS.tmp.$$"
  if ! jq --arg path "$cache_path" --arg ver "$version" --arg sha "$commit_sha" --arg now "$now" '
    .version = (.version // 2)
    | .plugins = (.plugins // {})
    | .plugins["implexa@implexa"] = [{
        scope: "user",
        installPath: $path,
        version: $ver,
        installedAt: ((.plugins["implexa@implexa"][0].installedAt) // $now),
        lastUpdated: $now,
        gitCommitSha: $sha
      }]
  ' "$INSTALLED_PLUGINS" > "$tmp_ip"; then
    rm -f "$tmp_ip"
    err "Failed to patch installed_plugins.json"
    return 1
  fi
  mv "$tmp_ip" "$INSTALLED_PLUGINS"

  ok "Implexa plugin installed (v$version)"
  return 0
}

if ! install_implexa_plugin; then
  print_plugin_fallback
fi

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
echo "  1. ${C_BOLD}Fully quit Claude${C_RESET} if it's already running"
echo "     (Cmd+Q on Mac — closing windows isn't enough; plugin/MCP load on launch)"
echo "  2. Launch Claude Code: ${C_BOLD}claude${C_RESET}"
echo "  3. Run ${C_BOLD}/implexa:help${C_RESET} to verify everything's wired"
echo "     You should see: the 7 commands + your credit balance"
echo "  4. Run ${C_BOLD}/implexa:record${C_RESET} to capture your first skill"
echo ""
echo "${C_BOLD}Claude Desktop / Cowork users:${C_RESET}"
echo "  The MCP server is registered, but the plugin's skills + slash commands"
echo "  need to be added separately: Customize → Personal plugins → Add marketplace"
echo "  → https://github.com/Implexa-Inc/implexa-claude-plugin"
echo ""
echo "Verify the capture worked: visit app.implexa.ai/skills/<your-skill-slug>/raw-capture"
echo "Both signals should be non-zero:"
echo "  - toolCallsCount > 0           (PostToolUse hook fired)"
echo "  - conversationTurns >= 2       (UserPromptSubmit + Stop hooks fired)"
echo ""
echo "Settings backup saved at: $BACKUP"
echo "(In case you ever need to restore: cp $BACKUP $SETTINGS)"
echo ""
