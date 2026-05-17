#!/usr/bin/env bash
#
# Implexa uninstall script — reverses everything install-user-hooks.sh did.
# ──────────────────────────────────────────────────────────────────────────
# Run with:
#   curl -fsSL https://core.implexa.ai/uninstall.sh | bash
#   # or, equivalently:
#   curl -fsSL https://raw.githubusercontent.com/Implexa-Inc/implexa-claude-plugin/main/scripts/uninstall.sh | bash
#
# What it does (idempotent — safe to re-run, exits 0 even when nothing's there):
#   1. Removes ~/.claude/implexa.env and ~/.claude/implexa-hook.sh
#   2. Removes the launchctl env vars (the macOS-wide source that survives
#      shell `unset` and re-leaks into new Terminal tabs)
#   3. Strips Implexa hooks from ~/.claude/settings.json (preserves other hooks)
#   4. Strips Implexa MCP server from claude_desktop_config.json
#   5. Removes the Implexa plugin from Claude Code:
#        - ~/.claude/plugins/marketplaces/implexa/
#        - ~/.claude/plugins/cache/implexa/
#        - entry in known_marketplaces.json
#        - entry in installed_plugins.json
#
# What it does NOT do:
#   - Does NOT revoke your API keys in the cloud. Revoke them at
#     https://app.implexa.ai/settings/api-keys if you want a fully clean slate.
#   - Does NOT log you out of the dashboard / delete your account.
#   - Does NOT touch Homebrew, jq, Node — those are user-installed dependencies
#     that may be needed for other software.
#
# After this finishes, `curl install.sh | bash` will be a true fresh install
# (device-auth flow runs, no env vars leak through).

set -e

CLAUDE_DIR="$HOME/.claude"
LAUNCHER="$CLAUDE_DIR/implexa-hook.sh"
CONFIG="$CLAUDE_DIR/implexa.env"
SETTINGS="$CLAUDE_DIR/settings.json"
DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
PLUGINS_DIR="$CLAUDE_DIR/plugins"
MARKETPLACE_DIR="$PLUGINS_DIR/marketplaces/implexa"
CACHE_DIR="$PLUGINS_DIR/cache/implexa"
KNOWN_MARKETPLACES="$PLUGINS_DIR/known_marketplaces.json"
INSTALLED_PLUGINS="$PLUGINS_DIR/installed_plugins.json"

# Color helpers — same as install script.
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
echo "${C_BOLD}🧹 Implexa uninstall${C_RESET}"
echo ""

# ─── 1. Remove config files ────────────────────────────────────────────
if [ -f "$CONFIG" ]; then
  rm -f "$CONFIG"
  ok "Removed $CONFIG"
else
  ok "$CONFIG — already absent"
fi

if [ -f "$LAUNCHER" ]; then
  rm -f "$LAUNCHER"
  ok "Removed $LAUNCHER"
else
  ok "$LAUNCHER — already absent"
fi

# ─── 2. Clear launchctl env vars ───────────────────────────────────────
# This is the macOS-wide leak source: the install script set these so GUI
# apps (Claude Desktop, Cowork) could find the API key. They persist across
# Terminal sessions and survive shell `unset` — anyone re-installing or
# testing a fresh signup flow needs these gone.
if [[ "$OSTYPE" == "darwin"* ]] && command -v launchctl >/dev/null 2>&1; then
  launchctl unsetenv IMPLEXA_API_KEY      2>/dev/null || true
  launchctl unsetenv IMPLEXA_API_URL      2>/dev/null || true
  launchctl unsetenv IMPLEXA_INSTALL_TOKEN 2>/dev/null || true
  ok "Cleared IMPLEXA_* from launchctl env"
fi

# ─── 3. Strip Implexa hooks from ~/.claude/settings.json ──────────────
# Removes any hook entries whose command references implexa-hook.sh, then
# tidies up empty matcher groups + empty hook arrays. Preserves all other
# hooks (Revenoid, custom user hooks, etc.).
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  TMP="$SETTINGS.tmp.$$"
  if jq '
    if .hooks then
      .hooks |= with_entries(
        .value |= map(
          .hooks |= map(select((.command // "") | test("implexa-hook.sh") | not))
        )
        | .value |= map(select(.hooks | length > 0))
      )
      | .hooks |= with_entries(select(.value | length > 0))
    else . end
  ' "$SETTINGS" > "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
    mv "$TMP" "$SETTINGS"
    ok "Removed Implexa hooks from $SETTINGS"
  else
    rm -f "$TMP"
    warn "Could not patch $SETTINGS automatically — open it and remove any 'implexa-hook.sh' hook entries manually."
  fi
elif [ -f "$SETTINGS" ]; then
  warn "jq not installed; can't clean hook entries from $SETTINGS automatically."
  echo "   To remove manually: open $SETTINGS and delete any hook entries referencing 'implexa-hook.sh'."
fi

# ─── 4. Strip Implexa MCP server from claude_desktop_config.json ──────
if [ -f "$DESKTOP_CFG" ] && command -v jq >/dev/null 2>&1; then
  TMP="$DESKTOP_CFG.tmp.$$"
  if jq 'if .mcpServers then .mcpServers |= del(.implexa) else . end' "$DESKTOP_CFG" > "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
    mv "$TMP" "$DESKTOP_CFG"
    ok "Removed Implexa MCP server from $DESKTOP_CFG"
  else
    rm -f "$TMP"
    warn "Could not patch $DESKTOP_CFG automatically — remove the 'implexa' entry under mcpServers manually."
  fi
fi

# ─── 5. Remove plugin from Claude Code ────────────────────────────────
if [ -d "$MARKETPLACE_DIR" ]; then
  rm -rf "$MARKETPLACE_DIR"
  ok "Removed $MARKETPLACE_DIR"
fi

if [ -d "$CACHE_DIR" ]; then
  rm -rf "$CACHE_DIR"
  ok "Removed $CACHE_DIR"
fi

# Patch known_marketplaces.json — remove the implexa entry
if [ -f "$KNOWN_MARKETPLACES" ] && command -v jq >/dev/null 2>&1; then
  TMP="$KNOWN_MARKETPLACES.tmp.$$"
  if jq 'del(.implexa)' "$KNOWN_MARKETPLACES" > "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
    mv "$TMP" "$KNOWN_MARKETPLACES"
    ok "Stripped implexa from known_marketplaces.json"
  else
    rm -f "$TMP"
  fi
fi

# Patch installed_plugins.json — remove the implexa@implexa entry
if [ -f "$INSTALLED_PLUGINS" ] && command -v jq >/dev/null 2>&1; then
  TMP="$INSTALLED_PLUGINS.tmp.$$"
  if jq 'if .plugins then .plugins |= del(."implexa@implexa") else . end' "$INSTALLED_PLUGINS" > "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
    mv "$TMP" "$INSTALLED_PLUGINS"
    ok "Stripped implexa@implexa from installed_plugins.json"
  else
    rm -f "$TMP"
  fi
fi

# ─── 6. Detect leftover env-var exports in shell startup files ───────
# We can't auto-delete user-editable config (too invasive without consent),
# but we CAN warn loudly when the leak source is sitting in their .zshrc /
# .zshenv / etc. — saves the "why is my fresh signup still picking up the
# old account?" frustration. We check the common interactive + non-interactive
# zsh/bash startup files.
LEAK_FILES=""
for f in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  [ -f "$f" ] || continue
  if grep -qE "IMPLEXA_API_KEY|IMPLEXA_INSTALL_TOKEN" "$f" 2>/dev/null; then
    LEAK_FILES="$LEAK_FILES $f"
  fi
done

echo ""
echo "${C_BOLD}${C_GREEN}🧹 Uninstall complete.${C_RESET}"
echo ""

# Show the env-leak warning ABOVE the "what's NOT removed" notes so it's the
# first thing the user sees — this is the highest-friction issue for anyone
# wanting to test a fresh install.
if [ -n "$LEAK_FILES" ]; then
  echo "${C_BOLD}${C_YELLOW}⚠ Action required for a fully fresh state:${C_RESET}"
  echo "${C_YELLOW}    Your shell startup file(s) still export IMPLEXA_API_KEY:${C_RESET}"
  for f in $LEAK_FILES; do
    line=$(grep -n "IMPLEXA_API_KEY\|IMPLEXA_INSTALL_TOKEN" "$f" 2>/dev/null | head -3)
    echo "${C_YELLOW}      $f:${C_RESET}"
    echo "$line" | sed 's/^/        /'
  done
  echo ""
  echo "${C_YELLOW}    These lines re-set the env var every time you open a new Terminal.${C_RESET}"
  echo "${C_YELLOW}    Remove them manually, then close + reopen Terminal. Quick option:${C_RESET}"
  echo ""
  for f in $LEAK_FILES; do
    echo "      sed -i.bak '/IMPLEXA_API_KEY\\|IMPLEXA_INSTALL_TOKEN/d' $f"
  done
  echo ""
  echo "${C_YELLOW}    (Creates a .bak in case you want to restore.)${C_RESET}"
  echo ""
fi

echo "${C_BOLD}What's NOT removed:${C_RESET}"
echo "  • Your API keys in the Implexa cloud are still active."
echo "    To revoke them: https://app.implexa.ai/settings/api-keys"
echo "  • Your Implexa account + skill library are untouched."
echo "  • Your settings.json backup files (~/.claude/settings.json.implexa-backup-*)"
echo "    Restore one with: cp <backup> ~/.claude/settings.json"
echo ""
echo "${C_BOLD}To reinstall:${C_RESET}"
echo "  curl -fsSL https://core.implexa.ai/install.sh | bash"
echo ""
