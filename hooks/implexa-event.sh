#!/usr/bin/env bash
# Implexa host-event hook.
#
# Wired into Claude Code via the plugin's settings.json on three events:
#   UserPromptSubmit  → /api/v2/mcp/demo-turn   (role=user)
#   Stop              → /api/v2/mcp/demo-turn   (role=assistant)
#   PostToolUse       → /api/v2/mcp/demo-tool-call
#
# Privacy guarantee: this script ONLY forwards data when an active demo
# session exists in the user's Implexa org. With no recording in progress,
# the backend returns 204 No Content and nothing is stored.
#
# Required env vars (set by the user once during install):
#   IMPLEXA_API_KEY   - imp_live_... key from app.implexa.ai/install
#   IMPLEXA_API_URL   - optional, defaults to https://core.implexa.ai
#
# Hook receives the event payload as JSON on stdin and the event name as $1.
# Hook is non-blocking — failures (no key, no network, no demo) silently exit 0.

set -e

EVENT_NAME="${1:-unknown}"
API_KEY="${IMPLEXA_API_KEY:-}"
API_URL="${IMPLEXA_API_URL:-https://core.implexa.ai}"

# Drop if no API key — user hasn't installed/configured Implexa yet.
if [ -z "$API_KEY" ]; then exit 0; fi

# Read stdin JSON payload (Claude Code sends event details this way).
PAYLOAD=$(cat -)
if [ -z "$PAYLOAD" ]; then exit 0; fi

# Pick the right endpoint + body shape per event.
case "$EVENT_NAME" in
  UserPromptSubmit)
    # Payload contains { prompt: "...", session_id: "...", ... }
    BODY=$(jq -c --arg role "user" '{role: $role, content: (.prompt // .user_prompt // "")}' <<< "$PAYLOAD" 2>/dev/null || echo "")
    ENDPOINT="/api/v2/mcp/demo-turn"
    ;;
  Stop)
    # Payload contains { response: "...", ... } when Claude finishes responding
    BODY=$(jq -c --arg role "assistant" '{role: $role, content: (.response // .assistant_response // .final_response // "")}' <<< "$PAYLOAD" 2>/dev/null || echo "")
    ENDPOINT="/api/v2/mcp/demo-turn"
    ;;
  PostToolUse)
    # Payload contains { tool_name, tool_args, tool_result, duration_ms }
    BODY=$(jq -c '{
      toolName:   (.tool_name // .toolName // "unknown"),
      toolArgs:   (.tool_args // .toolArgs // {}),
      toolResult: ((.tool_result // .toolResult) | tostring | .[0:1500]),
      durationMs: (.duration_ms // .durationMs // null)
    }' <<< "$PAYLOAD" 2>/dev/null || echo "")
    ENDPOINT="/api/v2/mcp/demo-tool-call"
    ;;
  *)
    # Unknown event — silently exit.
    exit 0
    ;;
esac

# If jq failed (e.g. invalid JSON in payload), drop silently.
if [ -z "$BODY" ]; then exit 0; fi

# Fire-and-forget POST. Timeout aggressively so a slow/offline backend
# never blocks Claude. We deliberately silence stderr — the user shouldn't
# see hook chatter in their Claude session.
curl --silent --max-time 3 --output /dev/null \
  -X POST "${API_URL}${ENDPOINT}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY" 2>/dev/null || true

exit 0
