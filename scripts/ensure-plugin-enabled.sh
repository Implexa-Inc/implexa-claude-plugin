#!/usr/bin/env bash
# Ensure the user-scoped Implexa plugin is enabled through Claude's supported
# CLI. This deliberately does not edit Claude-owned settings.json directly.

set -euo pipefail

PLUGIN_ID="implexa@implexa"
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || true)}"

if [ -z "$CLAUDE_BIN" ] || [ ! -x "$CLAUDE_BIN" ]; then
  echo "Claude command is unavailable; cannot verify plugin enabled state." >&2
  exit 1
fi

plugin_state() {
  (cd "$HOME" && "$CLAUDE_BIN" plugin list --json) 2>/dev/null \
    | jq -r --arg id "$PLUGIN_ID" '
        [.[] | select(.id == $id)] as $matches
        | if ($matches | length) != 1 then "missing"
          elif $matches[0].scope == "user" and $matches[0].enabled == true then "enabled"
          else "disabled"
          end
      ' 2>/dev/null
}

state=$(plugin_state || true)
case "$state" in
  enabled) exit 0 ;;
  disabled)
    # Another Claude process may enable it after our read. The command's exit
    # code is therefore advisory; the second independent read is authoritative.
    (cd "$HOME" && "$CLAUDE_BIN" plugin enable "$PLUGIN_ID" --scope user) >/dev/null 2>&1 || true
    [ "$(plugin_state || true)" = "enabled" ] || {
      echo "Claude did not confirm that $PLUGIN_ID is enabled." >&2
      exit 1
    }
    ;;
  *)
    echo "Claude does not report exactly one installed $PLUGIN_ID plugin." >&2
    exit 1
    ;;
esac
