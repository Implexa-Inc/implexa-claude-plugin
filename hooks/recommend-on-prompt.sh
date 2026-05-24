#!/usr/bin/env bash
# Implexa ambient recommender hook.
#
# Fires on every UserPromptSubmit. Surfaces ONE skill recommendation inline
# when the user's prompt semantically matches an aggregated skill above the
# backend's MIN_SCORE threshold. Silent otherwise.
#
# Wired via ~/.claude/settings.json (NOT the plugin's hooks.json) so this
# fires for users on Claude Code, Claude Desktop, and Cowork without needing
# plugin-packaged hook surfaces (Cowork sandboxes those).
#
# Discard-on-no-match privacy model
# ──────────────────────────────────
#  This script forwards the prompt to the backend, which only retains
#  prompts that produce a meaningful match. The hook itself does NOT log
#  prompt content anywhere; the optional debug log (IMPLEXA_HOOK_DEBUG=1)
#  records only the event type + payload size, never the prompt body.
#
# Required env vars (set by install-user-hooks.sh):
#   IMPLEXA_API_KEY   - imp_live_... key
#   IMPLEXA_API_URL   - optional, defaults to https://core.implexa.ai
#
# Non-blocking. Any failure exits 0 silently, we NEVER block the user's prompt
# with an error. This is a soft sidecar; if it can't talk to the backend it
# should disappear, not get in the way.

set -e

API_KEY="${IMPLEXA_API_KEY:-}"
API_URL="${IMPLEXA_API_URL:-https://core.implexa.ai}"

STATE_DIR="$HOME/.claude/plugins/implexa"
STATE_FILE="$STATE_DIR/recommender-state.json"
LOG_FILE="$HOME/.claude/implexa-recommend.log"

# Opt-in debug logging. Captures event metadata only, never prompt bodies.
hook_log() {
  if [ "${IMPLEXA_HOOK_DEBUG:-}" = "1" ]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '{"ts":"%s","stage":"%s","note":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-}" \
      >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# Silent exit on missing dependencies. Never block the user.
command -v jq   >/dev/null 2>&1 || { hook_log "no_jq" ""; exit 0; }
command -v curl >/dev/null 2>&1 || { hook_log "no_curl" ""; exit 0; }

if [ -z "$API_KEY" ]; then
  hook_log "no_key" ""
  exit 0
fi

PAYLOAD=$(cat -)
if [ -z "$PAYLOAD" ]; then
  hook_log "empty_stdin" ""
  exit 0
fi

EVENT_NAME=$(jq -r '.hook_event_name // empty' <<< "$PAYLOAD" 2>/dev/null)
if [ "$EVENT_NAME" != "UserPromptSubmit" ]; then
  exit 0
fi

PROMPT=$(jq -r '.prompt // empty' <<< "$PAYLOAD" 2>/dev/null)
if [ -z "$PROMPT" ]; then
  hook_log "empty_prompt" ""
  exit 0
fi

# ─── Gate 1: word count ─────────────────────────────────────────────────
# Filter "yes / ok / continue" style noise. Anything under 8 words is too
# short to semantic-match meaningfully against multi-paragraph SKILL.md
# descriptions.
WORD_COUNT=$(printf "%s" "$PROMPT" | wc -w | tr -d '[:space:]')
if [ "${WORD_COUNT:-0}" -lt 8 ]; then
  hook_log "too_short" "$WORD_COUNT"
  exit 0
fi

# ─── State file ─────────────────────────────────────────────────────────
mkdir -p "$STATE_DIR" 2>/dev/null || true
if [ ! -f "$STATE_FILE" ]; then
  # Generate a session id (RFC 4122-ish). uuidgen is on macOS by default;
  # fall back to /dev/urandom if missing.
  if command -v uuidgen >/dev/null 2>&1; then
    SID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  else
    SID=$(od -x -N 16 /dev/urandom | head -1 | awk '{print $2$3"-"$4"-"$5"-"$6"-"$7$8$9}')
  fi
  jq -n --arg sid "$SID" '{
    session_id: $sid,
    last_fired_at: 0,
    suppress_counter: 0,
    mute_session: false,
    recent_recommendations: [],
    consecutive_dismissals: 0
  }' > "$STATE_FILE" 2>/dev/null || { hook_log "state_init_failed" ""; exit 0; }
fi

# Read state. If anything is malformed, treat it as if all gates pass.
SESSION_ID=$(jq -r '.session_id // empty' "$STATE_FILE" 2>/dev/null)
SUPPRESS=$(jq -r '.suppress_counter // 0' "$STATE_FILE" 2>/dev/null)
MUTE=$(jq -r '.mute_session // false' "$STATE_FILE" 2>/dev/null)
LAST_FIRED=$(jq -r '.last_fired_at // 0' "$STATE_FILE" 2>/dev/null)
CONSEC_DISMISS=$(jq -r '.consecutive_dismissals // 0' "$STATE_FILE" 2>/dev/null)

# ─── Gate 2: session mute ───────────────────────────────────────────────
if [ "$MUTE" = "true" ]; then
  hook_log "muted_session" ""
  exit 0
fi

# ─── Gate 3: suppression counter ────────────────────────────────────────
# Decrement and exit when active. The backend hints suppress_until_prompts
# on every no-match response; we honor it client-side so we don't hammer
# the API with prompts known to not match anything.
if [ "${SUPPRESS:-0}" -gt 0 ]; then
  NEW_SUPPRESS=$(( SUPPRESS - 1 ))
  TMP="$STATE_FILE.tmp.$$"
  jq --argjson n "$NEW_SUPPRESS" '.suppress_counter = $n' "$STATE_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$STATE_FILE"
  hook_log "suppressed" "$NEW_SUPPRESS"
  exit 0
fi

# ─── Gate 4: rate limit (90s since last fire) ───────────────────────────
NOW_S=$(date +%s)
SINCE=$(( NOW_S - LAST_FIRED ))
if [ "$LAST_FIRED" -gt 0 ] && [ "$SINCE" -lt 90 ]; then
  hook_log "rate_limited" "$SINCE"
  exit 0
fi

# ─── Build messages array from session transcript ───────────────────────
# Claude Code passes transcript_path to the hook. Read the last 4 user
# messages from the JSONL transcript for richer context. Falls back to
# just the current prompt if the transcript isn't readable.
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<< "$PAYLOAD" 2>/dev/null)
LAST_PROMPTS_JSON='[]'
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # Reverse-walk transcript JSONL, pick last 3 user lines, then add current.
  if command -v tac >/dev/null 2>&1; then
    REVERSE=(tac)
  else
    REVERSE=(tail -r)
  fi
  LAST_PROMPTS_JSON=$(
    "${REVERSE[@]}" "$TRANSCRIPT" 2>/dev/null \
      | jq -r 'select((.role // .message.role // .type) == "user") | (.content // .message.content // .text // "") | if type == "array" then (map(.text // .) | join("\n")) else . end' 2>/dev/null \
      | grep -v '^$' \
      | head -n 3 \
      | "${REVERSE[@]}" \
      | jq -R -s -c 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]'
  )
fi

# Append the current prompt; ensure final array length is <= 5.
MESSAGES_JSON=$(jq -c --arg p "$PROMPT" '. + [$p] | .[-5:]' <<< "$LAST_PROMPTS_JSON" 2>/dev/null || echo "[\"$PROMPT\"]")

# ─── Find list of already-installed slugs (best-effort) ─────────────────
# Read from any plugin-cached install file if present. Worst case we send
# an empty list and the backend may surface something the user has (rare for
# cross-vendor aggregated skills which are different IDs anyway).
EXCLUDE_JSON='[]'
INSTALL_LOG="$HOME/.claude/plugins/implexa/installed-slugs.json"
if [ -f "$INSTALL_LOG" ]; then
  EXCLUDE_JSON=$(cat "$INSTALL_LOG" 2>/dev/null || echo '[]')
fi

# Also exclude anything we've recommended in the last 30 minutes (per-slug
# cooldown). Read recent_recommendations from state.
RECENT_SLUGS=$(jq -c --argjson now "$NOW_S" '
  [.recent_recommendations[]?
    | select((.timestamp // 0) > ($now - 1800))
    | .slug
    | select(. != null and . != "")]
' "$STATE_FILE" 2>/dev/null || echo '[]')
EXCLUDE_JSON=$(jq -c -n --argjson a "$EXCLUDE_JSON" --argjson b "$RECENT_SLUGS" '$a + $b | unique' 2>/dev/null || echo '[]')

# ─── Build the MCP JSON-RPC tools/call request ──────────────────────────
RPC_BODY=$(jq -n \
  --argjson messages "$MESSAGES_JSON" \
  --argjson exclude  "$EXCLUDE_JSON" \
  --arg     sid      "$SESSION_ID" \
  '{
    jsonrpc: "2.0",
    id: "implexa-ambient",
    method: "tools/call",
    params: {
      name: "recommend_skills_for_context",
      arguments: {
        messages: $messages,
        topN: 1,
        excludeAlreadyInstalled: $exclude,
        sessionId: $sid
      }
    }
  }' 2>/dev/null)

if [ -z "$RPC_BODY" ]; then
  hook_log "rpc_body_failed" ""
  exit 0
fi

# ─── Fire the request (3s timeout) ──────────────────────────────────────
RESPONSE=$(curl --silent --max-time 3 \
  -X POST "${API_URL}/api/v2/mcp" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d "$RPC_BODY" 2>/dev/null || echo "")

if [ -z "$RESPONSE" ]; then
  hook_log "no_response" ""
  exit 0
fi

# MCP streamable HTTP can return either application/json OR text/event-stream.
# For SSE responses, extract the data: lines and join them; for JSON, pass through.
if printf '%s' "$RESPONSE" | head -c 6 | grep -q '^event:\|^data:'; then
  RESPONSE_JSON=$(printf '%s' "$RESPONSE" | awk '/^data: /{sub(/^data: /, ""); print}' | head -1)
else
  RESPONSE_JSON="$RESPONSE"
fi

# ─── Parse the response ─────────────────────────────────────────────────
# MCP tool responses are wrapped: { result: { content: [{ type: "text", text: "{...json...}" }] } }
INNER=$(jq -r '.result.content[0].text // empty' <<< "$RESPONSE_JSON" 2>/dev/null)
if [ -z "$INNER" ]; then
  # Backend returned an error or unexpected shape. Silent exit; never block.
  hook_log "no_inner_text" ""
  exit 0
fi

MATCHES_COUNT=$(jq -r '.matches | length // 0' <<< "$INNER" 2>/dev/null)
SUPPRESS_HINT=$(jq -r '.suppress_until_prompts // 0' <<< "$INNER" 2>/dev/null)

# ─── No-match path ──────────────────────────────────────────────────────
if [ "${MATCHES_COUNT:-0}" -eq 0 ]; then
  # Honor the backend's backoff hint. Update state, exit silent.
  TMP="$STATE_FILE.tmp.$$"
  jq --argjson s "${SUPPRESS_HINT:-10}" --argjson now "$NOW_S" \
    '.suppress_counter = $s | .last_fired_at = $now' \
    "$STATE_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$STATE_FILE"
  hook_log "no_match" "$SUPPRESS_HINT"
  exit 0
fi

# ─── Positive match: surface inline ─────────────────────────────────────
# Extract the top match. Print to stdout so Claude Code surfaces it inline
# to both the user AND the model. Cadence: lowercase, punchy, no em-dashes.
NAME=$(jq -r '.matches[0].name        // empty' <<< "$INNER" 2>/dev/null)
SLUG=$(jq -r '.matches[0].slug        // empty' <<< "$INNER" 2>/dev/null)
FIT=$(jq  -r '.matches[0].fit_reason  // empty' <<< "$INNER" 2>/dev/null)
URL=$(jq  -r '.matches[0].install_hint // empty' <<< "$INNER" 2>/dev/null)
SOURCE=$(jq -r '.matches[0].source    // empty' <<< "$INNER" 2>/dev/null)

if [ -z "$NAME" ] || [ -z "$SLUG" ]; then
  hook_log "missing_fields" ""
  exit 0
fi

# Mute prompt threshold check. If user has dismissed 3 in a row, include
# a one-time mute affordance.
MUTE_AFFORDANCE=""
if [ "${CONSEC_DISMISS:-0}" -ge 3 ]; then
  MUTE_AFFORDANCE=$'\n  (implexa muted for this project? reply "mute implexa", or "keep watching")'
fi

# Output to stdout. Claude Code injects this into the user-facing transcript
# AND the model context. Single block, no em-dashes, lowercase cadence.
printf '\n💡 implexa might help here:\n  • %s: %s\n    install: %s\n    [%s]%s\n' \
  "$NAME" "$FIT" "$URL" "$SOURCE" "$MUTE_AFFORDANCE"

# Update state: bump last_fired_at, push recent_recommendations, reset
# suppress_counter (we got a hit; the user is in interesting territory).
TMP="$STATE_FILE.tmp.$$"
jq --arg slug "$SLUG" --argjson now "$NOW_S" '
  .last_fired_at = $now
  | .suppress_counter = 0
  | .recent_recommendations = (
      [.recent_recommendations[]? | select((.timestamp // 0) > ($now - 7200))]
      + [{slug: $slug, timestamp: $now, dismissed: false}]
    )
' "$STATE_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$STATE_FILE"

hook_log "surfaced" "$SLUG"
exit 0
