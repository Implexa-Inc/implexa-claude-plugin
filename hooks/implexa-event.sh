#!/usr/bin/env bash
# Implexa host-event hook.
#
# Wired into Claude Code via hooks/hooks.json for three events:
#   UserPromptSubmit  → /api/v2/mcp/demo-turn      (role=user)
#   Stop              → /api/v2/mcp/demo-turn      (role=assistant)
#   PostToolUse       → /api/v2/mcp/demo-tool-call
#
# Per docs (https://code.claude.com/docs/en/hooks), Claude Code passes the
# event payload as JSON on stdin (NOT as command-line args). The event name
# is in the .hook_event_name field — we read it from stdin, not from $1.
#
# Privacy guarantee: this script ONLY forwards data when an active demo
# session exists in the user's Implexa org. With no recording in progress,
# the backend returns 204 No Content and nothing is stored.
#
# Required env vars (set by user during install):
#   IMPLEXA_API_KEY   - imp_live_... key from app.implexa.ai/install
#   IMPLEXA_API_URL   - optional, defaults to https://core.implexa.ai
#
# Hook is non-blocking — failures (no key, no network, no demo) silently exit 0.

set -e

API_KEY="${IMPLEXA_API_KEY:-}"
API_URL="${IMPLEXA_API_URL:-https://core.implexa.ai}"

# Drop if no API key — user hasn't installed/configured Implexa yet.
if [ -z "$API_KEY" ]; then exit 0; fi

# Read stdin JSON payload (Claude Code sends event details this way).
PAYLOAD=$(cat -)
if [ -z "$PAYLOAD" ]; then exit 0; fi

# Read the event name from the payload itself, per Claude Code docs.
EVENT_NAME=$(jq -r '.hook_event_name // empty' <<< "$PAYLOAD" 2>/dev/null)
if [ -z "$EVENT_NAME" ]; then exit 0; fi

# Pick the right endpoint + body shape per event.
case "$EVENT_NAME" in
  UserPromptSubmit)
    # Schema: { hook_event_name, session_id, transcript_path, cwd, permission_mode, prompt }
    BODY=$(jq -c '{role: "user", content: (.prompt // "")}' <<< "$PAYLOAD" 2>/dev/null || echo "")
    ENDPOINT="/api/v2/mcp/demo-turn"
    ;;

  Stop)
    # Schema not fully documented. Best path: read the last assistant message
    # from the transcript_path (JSONL of the session). Falls back to a marker
    # if transcript isn't accessible.
    TRANSCRIPT=$(jq -r '.transcript_path // empty' <<< "$PAYLOAD" 2>/dev/null)
    LAST_RESPONSE=""
    if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
      # Find the last line with role=assistant; truncate to 8KB to keep body sane.
      LAST_RESPONSE=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m 1 '"role":"assistant"' \
        | jq -r '(.content // .message.content // .text // "") | if type == "array" then (map(.text // .) | join("\n")) else . end' 2>/dev/null \
        | head -c 8192 || echo "")
    fi
    # If we couldn't read the transcript, send a minimal marker so backend
    # knows the assistant finished a turn (better than nothing).
    if [ -z "$LAST_RESPONSE" ]; then LAST_RESPONSE="(assistant turn completed)"; fi
    BODY=$(jq -c --arg content "$LAST_RESPONSE" '{role: "assistant", content: $content}' <<< "$PAYLOAD" 2>/dev/null || echo "")
    ENDPOINT="/api/v2/mcp/demo-turn"
    ;;

  PostToolUse)
    # Schema: { hook_event_name, session_id, transcript_path, cwd, permission_mode,
    #          effort, tool_name, tool_input, tool_response }
    BODY=$(jq -c '{
      toolName:   (.tool_name // "unknown"),
      toolArgs:   (.tool_input // {}),
      toolResult: ((.tool_response // "") | tostring | .[0:1500])
    }' <<< "$PAYLOAD" 2>/dev/null || echo "")
    ENDPOINT="/api/v2/mcp/demo-tool-call"
    ;;

  *)
    exit 0
    ;;
esac

if [ -z "$BODY" ]; then exit 0; fi

# Fire-and-forget POST. 3s timeout so slow/offline backend never blocks Claude.
curl --silent --max-time 3 --output /dev/null \
  -X POST "${API_URL}${ENDPOINT}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY" 2>/dev/null || true

exit 0
