#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/implexa-claude-config-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
CONFIG="$TMP/claude_desktop_config.json"

# Model a macOS launchd session without reading any real environment value.
# The helper must issue the exact fixed unset list and never call getenv.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/uname" <<'SH'
#!/bin/sh
printf 'Darwin\n'
SH
cat > "$TMP/bin/launchctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$IMPLEXA_LAUNCHCTL_AUDIT"
SH
chmod +x "$TMP/bin/uname" "$TMP/bin/launchctl"
export IMPLEXA_LAUNCHCTL_AUDIT="$TMP/launchctl.audit"
PATH="$TMP/bin:$PATH" "$ROOT/scripts/remove-legacy-claude-mcp.sh" "$TMP/absent.json"
cat > "$TMP/expected.audit" <<'EOF'
unsetenv IMPLEXA_API_KEY
unsetenv IMPLEXA_API_URL
unsetenv IMPLEXA_INSTALL_TOKEN
unsetenv IMPLEXA_API_BASE_URL
unsetenv IMPLEXA_HOOK_DEBUG
EOF
cmp "$TMP/launchctl.audit" "$TMP/expected.audit"
if grep -q 'getenv' "$TMP/launchctl.audit"; then
  echo 'legacy launch environment was read' >&2
  exit 1
fi
rm -f "$TMP/launchctl.audit"

cat > "$CONFIG" <<'JSON'
{
  "theme": "dark",
  "mcpServers": {
    "other": {"command": "other"},
    "implexa": {"command": "npx", "args": ["-y", "@implexa/mcp-server"], "env": {"IMPLEXA_API_KEY": "secret"}},
    "implexa-managed": {"command": "foreign-stale"},
    "implexa_managed": {"command": "foreign-stale-2"}
  }
}
JSON
chmod 644 "$CONFIG"
PATH="$TMP/bin:$PATH" "$ROOT/scripts/remove-legacy-claude-mcp.sh" "$CONFIG"
[ "$(jq -r '.theme' "$CONFIG")" = "dark" ]
[ "$(jq -r '.mcpServers.other.command' "$CONFIG")" = "other" ]
[ "$(jq -r '.mcpServers | has("implexa") or has("implexa-managed") or has("implexa_managed")' "$CONFIG")" = "false" ]
[ "$(stat -f '%Lp' "$CONFIG" 2>/dev/null || stat -c '%a' "$CONFIG")" = "600" ]

cp "$CONFIG" "$CONFIG.before"
PATH="$TMP/bin:$PATH" "$ROOT/scripts/remove-legacy-claude-mcp.sh" "$CONFIG"
cmp "$CONFIG" "$CONFIG.before"

printf '{broken' > "$CONFIG"
cp "$CONFIG" "$CONFIG.before"
if PATH="$TMP/bin:$PATH" "$ROOT/scripts/remove-legacy-claude-mcp.sh" "$CONFIG" >/dev/null 2>&1; then
  echo 'malformed config was accepted' >&2
  exit 1
fi
cmp "$CONFIG" "$CONFIG.before"

printf '%s\n' 'legacy Claude MCP migration: 10/10 passed'
