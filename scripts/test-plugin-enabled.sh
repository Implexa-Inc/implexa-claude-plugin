#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/claude"
STATE="$TMP/state"

grep -F '"$MARKETPLACE_PATH/scripts/ensure-plugin-enabled.sh"' "$ROOT/scripts/install-user-hooks.sh" >/dev/null
if grep -q 'enabledPlugins' "$ROOT/scripts/install-user-hooks.sh"; then
  echo "installer must use Claude CLI rather than patch enabledPlugins" >&2
  exit 1
fi

cat > "$FAKE" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-} ${3:-}" in
  "plugin list --json")
    enabled=false; [ "$(cat "$FAKE_STATE" 2>/dev/null || true)" = enabled ] && enabled=true
    printf '[{"id":"other@other","scope":"user","enabled":true},{"id":"implexa@implexa","scope":"user","enabled":%s}]\n' "$enabled"
    ;;
  "plugin enable implexa@implexa")
    [ "${4:-} ${5:-}" = "--scope user" ]
    printf enabled > "$FAKE_STATE"
    ;;
  *) exit 64 ;;
esac
SH
chmod +x "$FAKE"

FAKE_STATE="$STATE" CLAUDE_BIN="$FAKE" "$ROOT/scripts/ensure-plugin-enabled.sh"
[ "$(cat "$STATE")" = enabled ]

# Idempotency: an enabled plugin must not call the enable command again.
cat > "$FAKE" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-} ${2:-} ${3:-}" = "plugin list --json" ]; then
  printf '[{"id":"implexa@implexa","scope":"user","enabled":true}]\n'
  exit 0
fi
exit 73
SH
chmod +x "$FAKE"
CLAUDE_BIN="$FAKE" "$ROOT/scripts/ensure-plugin-enabled.sh"

# A project override is not global user readiness; repair the user scope.
rm -f "$STATE"
cat > "$FAKE" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-} ${2:-} ${3:-}" = "plugin list --json" ]; then
  if [ "$(cat "$FAKE_STATE" 2>/dev/null || true)" = enabled ]; then scope=user; else scope=project; fi
  printf '[{"id":"implexa@implexa","scope":"%s","enabled":true}]\n' "$scope"
elif [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "plugin enable implexa@implexa --scope user" ]; then
  printf enabled > "$FAKE_STATE"
else exit 75
fi
SH
chmod +x "$FAKE"
FAKE_STATE="$STATE" CLAUDE_BIN="$FAKE" "$ROOT/scripts/ensure-plugin-enabled.sh"
[ "$(cat "$STATE")" = enabled ]

# Missing and ambiguous registry entries fail closed.
for payload in '[]' '[{"id":"implexa@implexa","scope":"user","enabled":false},{"id":"implexa@implexa","scope":"user","enabled":true}]'; do
  printf '%s' "$payload" > "$TMP/payload"
  cat > "$FAKE" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-} ${2:-} ${3:-}" = "plugin list --json" ]; then cat "$FAKE_PAYLOAD"; exit 0; fi
exit 74
SH
  chmod +x "$FAKE"
  if FAKE_PAYLOAD="$TMP/payload" CLAUDE_BIN="$FAKE" "$ROOT/scripts/ensure-plugin-enabled.sh" >/dev/null 2>&1; then
    echo "invalid plugin state was accepted" >&2
    exit 1
  fi
done

echo "plugin enabled-state tests passed"
