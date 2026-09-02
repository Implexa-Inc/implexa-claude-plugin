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
#   3. Writes ~/.claude/implexa.env       — config file (chmod 600)
#   4. Removes the retired duplicate direct MCP definition
#   5. Prunes any retired user-level Implexa hooks from settings.json
#      (the old ambient-capture + recommender launchers)
#   6. Auto-installs and enables the Implexa plugin in Claude Code
#   7. Backs up your previous settings.json
#
# Implexa is app-first: you build, run, approve, and schedule agents in the
# Implexa app, and Claude runs them in the background. The plugin's own
# background hooks (queue drain on session start, permission-stall safety)
# ship in the plugin's hooks/hooks.json and load directly — this script does
# NOT install any user-level prompt/tool hooks. Earlier versions wired an
# ambient capture + recommender at the user level; section 8 below removes
# those on upgrade.
#
# After this script: fully quit Claude (Cmd+Q on Mac) and relaunch.

set -e

# If Homebrew is installed but not on PATH (common right after first install
# before the user has restarted their shell), proactively add it for jq/git.
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
  echo "    jq if missing. The Implexa MCP transport itself needs no npm runtime."
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

# ─── 3b. MCP runtime ────────────────────────────────────────────────────
# The MCP transport is shipped with this plugin and uses only macOS system
# binaries. It never downloads or executes npm packages at runtime.
ok "Versioned local MCP transport included"

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
# Implexa config — auto-generated by install-user-hooks.sh
# Holds your API key + API URL for the plugin's background hooks only. The MCP
# server does not read this file: it uses Implexa Desktop's revocable local
# broker, so no account credential enters Claude's MCP configuration.
export IMPLEXA_API_KEY="$API_KEY"
export IMPLEXA_API_URL="https://core.implexa.ai"
EOF
chmod 600 "$CONFIG"
ok "Wrote config: $CONFIG (chmod 600 — only you can read it)"

# ─── 6b. Retired direct MCP definition ─────────────────────────────────
# Removal runs after the marketplace clone is refreshed, using the versioned
# migration helper shipped in the plugin. This standalone installer therefore
# has one audited implementation rather than a second inline JSON rewrite.
DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

# ─── 7+8. Migrate: prune retired user-level Implexa hooks ──────────────
# Implexa is app-first now. Earlier versions installed two USER-LEVEL hooks
# here: an ambient capture launcher (~/.claude/implexa-hook.sh) under
# UserPromptSubmit/Stop/PostToolUse, and an ambient recommender
# (~/.claude/implexa-recommend.sh) under UserPromptSubmit. Both are retired.
# This step removes them from settings.json so existing installs don't point
# at deleted plugin hook files, then tidies up empty matcher groups + empty
# event arrays. Preserves all other hooks.
#
# The plugin's own background hooks (queue drain on session start,
# permission-stall safety) ship in the plugin's hooks/hooks.json and are
# loaded by Claude Code directly — they are NOT registered or touched here.
#
# Uses jq (a hard dep above) instead of python3 — fresh Macs lack a working
# /usr/bin/python3 (it triggers an Xcode CLT install dialog).
HOOK_LAUNCHER_CMD='$HOME/.claude/implexa-hook.sh'
RECOMMEND_LAUNCHER_CMD='$HOME/.claude/implexa-recommend.sh'
TMP_SETTINGS="$SETTINGS.tmp.$$"
if jq --arg c1 "$HOOK_LAUNCHER_CMD" --arg c2 "$RECOMMEND_LAUNCHER_CMD" '
  if .hooks then
    .hooks |= with_entries(
      .value |= (
        map(.hooks = ((.hooks // []) | map(select(.command != $c1 and .command != $c2))))
        | map(select((.hooks | length) > 0))
      )
    )
    | .hooks |= with_entries(select((.value | length) > 0))
  else . end
' "$SETTINGS" > "$TMP_SETTINGS" 2>/dev/null && [ -s "$TMP_SETTINGS" ]; then
  mv "$TMP_SETTINGS" "$SETTINGS"
  ok "Pruned any retired Implexa user-level hooks from settings.json"
else
  rm -f "$TMP_SETTINGS"
  warn "Could not prune legacy hooks from $SETTINGS (it may already be clean)."
fi

# Remove the now-orphaned launcher scripts left by older installs.
for _legacy in "$LAUNCHER" "$CLAUDE_DIR/implexa-recommend.sh"; do
  if [ -e "$_legacy" ]; then
    rm -f "$_legacy" && ok "Removed legacy launcher: $_legacy"
  fi
done

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


# ─── 8e. SkillRank phase A — data-collection consent ───────────────────
# Implexa's recommender gets dramatically better with three signals on
# top of semantic match (tool stack overlap, work-signature similarity,
# outcome attribution). Two of those are low-sensitivity and default on.
# One — work signature for cohort matching — is more sensitive and
# defaults OFF unless the user explicitly opts in.
#
# What gets written:
#   1. ~/.claude/plugins/implexa/consent.json — the on-disk record of the
#      user's data preferences, retained for local tooling compatibility.
#   2. POST /api/v2/mcp record_consent — the backend mirror, source of
#      truth for record_work_signature's gate (the app-first recommender
#      reads these preferences server-side).
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

  # Registration and activation are separate Claude states. Use Claude's
  # supported command to repair fresh installs, upgrades, and previously
  # disabled plugins; never patch Claude's activation map ourselves.
  if ! "$MARKETPLACE_PATH/scripts/ensure-plugin-enabled.sh"; then
    err "Plugin files were installed, but Claude did not enable implexa@implexa"
    return 1
  fi

  ok "Implexa plugin installed and enabled (v$version)"
  return 0
}

if ! install_implexa_plugin; then
  print_plugin_fallback
elif [ -x "$MARKETPLACE_PATH/scripts/remove-legacy-claude-mcp.sh" ]; then
  if [ -f "$DESKTOP_CFG" ]; then
    cp "$DESKTOP_CFG" "$DESKTOP_CFG.implexa-backup-$(date +%s)"
  fi
  "$MARKETPLACE_PATH/scripts/remove-legacy-claude-mcp.sh" "$DESKTOP_CFG"
  ok "Removed retired duplicate Implexa MCP definitions"
fi

# ─── 9. Smoke test ─────────────────────────────────────────────────────
echo ""
info "Running smoke test (verifying the plugin + config are in place)..."

# Check the plugin is actually findable. The plugin's background hooks live in
# its hooks/hooks.json; we probe for a known kept hook (pending-runs-on-start.sh)
# across the two install locations: CLI (~/.claude/plugins/cache/...) and
# Desktop (~/Library/Application Support/Claude/local-agent-mode-sessions/...).
PLUGIN_HOOK=$(
  {
    ls -t "$HOME/.claude/plugins/cache/implexa/implexa/"*/hooks/pending-runs-on-start.sh 2>/dev/null
    ls -t "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/"*/*/rpm/plugin_*/hooks/pending-runs-on-start.sh 2>/dev/null
  } | head -n 1
)
if [ -z "$PLUGIN_HOOK" ]; then
  warn "Implexa plugin not found in either install location:"
  echo "    - $HOME/.claude/plugins/cache/implexa/implexa/  (Claude Code CLI)"
  echo "    - $HOME/Library/Application Support/Claude/local-agent-mode-sessions/.../rpm/plugin_.../  (Claude Desktop)"
  echo ""
  echo "    The hook config is in place; the managed MCP transport arrives with the plugin."
  echo "    If you've already installed the Implexa plugin in Claude Desktop"
  echo "    (Customize → Personal plugins → Add marketplace → Install) but still see this,"
  echo "    please report it: https://github.com/Implexa-Inc/implexa-claude-plugin/issues"
else
  ok "Plugin found at $PLUGIN_HOOK"
fi

if "$MARKETPLACE_PATH/scripts/ensure-plugin-enabled.sh"; then
  ok "Plugin enabled in Claude"
else
  err "Plugin is installed but not enabled. Run: claude plugin enable implexa@implexa --scope user"
  exit 1
fi

# Confirm the config exists and settings.json is still valid JSON after our patches.
if [ -r "$CONFIG" ]; then
  ok "Config present at $CONFIG"
else
  warn "Config not found at $CONFIG — re-run the installer if the MCP server can't authenticate."
fi
if jq empty "$SETTINGS" >/dev/null 2>&1; then
  ok "settings.json is valid JSON"
else
  err "settings.json is not valid JSON after patching. Restore the backup: cp $BACKUP $SETTINGS"
  exit 1
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
echo "     You should see how Implexa works + your credit balance"
echo "  4. Build your first agent at ${C_BOLD}https://app.implexa.ai${C_RESET}"
echo "     (or just ask Claude: \"build me an agent that …\")"
echo ""
echo "${C_BOLD}Claude Desktop / Cowork users:${C_RESET}"
echo "  If the plugin is not visible after restart, add it from Customize → Personal"
echo "  plugins → Add marketplace → https://github.com/Implexa-Inc/implexa-claude-plugin"
echo "  The managed MCP transport is part of that plugin; no second server entry is needed."
echo ""
echo "Implexa is app-first: build, run, approve, and schedule your agents at"
echo "https://app.implexa.ai — Claude runs them in the background."
echo ""
echo "Settings backup saved at: $BACKUP"
echo "(In case you ever need to restore: cp $BACKUP $SETTINGS)"
echo ""
