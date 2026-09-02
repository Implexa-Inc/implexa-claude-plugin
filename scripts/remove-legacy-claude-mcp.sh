#!/bin/sh
# Remove only Implexa's retired direct MCP registrations. The plugin now owns
# the single managed definition. Unrelated Claude Desktop settings and servers
# are preserved byte-semantically through jq's parsed representation.
set -eu

# Older installers persisted credentials into the per-login launchd environment.
# The managed MCP transport uses Desktop's local auth broker, so those inherited
# values are both unnecessary and dangerous. Never read or print them: remove
# only the fixed historical names, idempotently, for future app launches.
scrub_legacy_launch_environment() {
  [ "$(uname -s 2>/dev/null || true)" = "Darwin" ] || return 0
  command -v launchctl >/dev/null 2>&1 || return 0
  for name in \
    IMPLEXA_API_KEY \
    IMPLEXA_API_URL \
    IMPLEXA_INSTALL_TOKEN \
    IMPLEXA_API_BASE_URL \
    IMPLEXA_HOOK_DEBUG
  do
    launchctl unsetenv "$name" >/dev/null 2>&1 || true
  done
}

scrub_legacy_launch_environment

CONFIG="${1:-$HOME/Library/Application Support/Claude/claude_desktop_config.json}"
[ -e "$CONFIG" ] || exit 0
[ -f "$CONFIG" ] && [ ! -L "$CONFIG" ] || {
  echo "Refusing an unsafe Claude Desktop config path." >&2
  exit 1
}

TMP="$(mktemp "$CONFIG.implexa.tmp.XXXXXX")"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
if ! /usr/bin/env jq '
  if (.mcpServers? | type) == "object" then
    .mcpServers |= del(.implexa, .["implexa-managed"], .implexa_managed)
    | if (.mcpServers | length) == 0 then del(.mcpServers) else . end
  else . end
' "$CONFIG" > "$TMP"; then
  echo "Claude Desktop config is not valid JSON; original left unchanged." >&2
  exit 1
fi
chmod 600 "$TMP"
mv "$TMP" "$CONFIG"
trap - EXIT HUP INT TERM
