#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/implexa-claude-config-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
CONFIG="$TMP/claude_desktop_config.json"

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
"$ROOT/scripts/remove-legacy-claude-mcp.sh" "$CONFIG"
[ "$(jq -r '.theme' "$CONFIG")" = "dark" ]
[ "$(jq -r '.mcpServers.other.command' "$CONFIG")" = "other" ]
[ "$(jq -r '.mcpServers | has("implexa") or has("implexa-managed") or has("implexa_managed")' "$CONFIG")" = "false" ]
[ "$(stat -f '%Lp' "$CONFIG" 2>/dev/null || stat -c '%a' "$CONFIG")" = "600" ]

cp "$CONFIG" "$CONFIG.before"
"$ROOT/scripts/remove-legacy-claude-mcp.sh" "$CONFIG"
cmp "$CONFIG" "$CONFIG.before"

printf '{broken' > "$CONFIG"
cp "$CONFIG" "$CONFIG.before"
if "$ROOT/scripts/remove-legacy-claude-mcp.sh" "$CONFIG" >/dev/null 2>&1; then
  echo 'malformed config was accepted' >&2
  exit 1
fi
cmp "$CONFIG" "$CONFIG.before"

printf '%s\n' 'legacy Claude MCP migration: 7/7 passed'
