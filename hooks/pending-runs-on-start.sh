#!/usr/bin/env bash
# Implexa pending-runs SessionStart hook (consumer run-once bus).
#
# The consumer composes an agent in the Implexa desktop app and taps "run once".
# The desktop cannot reach into Claude/Codex directly, so it enqueues a
# run-request on the backend. When the user's AI app next opens, THIS hook fires,
# reads the user's pending run-requests via the get_pending_run_requests MCP tool
# (over the same /api/v2/mcp channel the recommender uses), and, if any are
# pending, injects an honest one-line offer to run them.
#
# Model-safety: this surfaces a USER-INITIATED action (the user composed the
# agent in Implexa desktop and asked to run it). The framing is honest and
# non-imperative: "the user did X, offer to run it, let them decide." It is not
# an injected instruction to act unilaterally. apply_workflow keeps its own
# approval gates for anything irreversible.
#
# Required env (set by install-user-hooks.sh):
#   IMPLEXA_API_KEY   imp_live_... key (identifies the user server-side)
#   IMPLEXA_API_URL   optional, defaults to https://core.implexa.ai
#
# Non-blocking. Any failure / missing dep / no pending requests exits 0 silently
# with NO model-visible output.

set -o pipefail

API_KEY="${IMPLEXA_API_KEY:-}"
API_URL="${IMPLEXA_API_URL:-https://core.implexa.ai}"
PLUGIN_VERSION="0.27.7"

# Silent no-ops: missing key or deps. Never block or error the session.
[ -z "$API_KEY" ] && exit 0
command -v jq   >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

# Drain stdin (Claude sends the SessionStart payload as JSON); we do not need
# any field from it, but reading avoids a broken-pipe on the caller's side.
cat >/dev/null 2>&1 || true

# ── Call get_pending_run_requests over the MCP HTTP channel ──────────────────
body=$(jq -n '{
  jsonrpc: "2.0",
  id: "implexa-pending-runs",
  method: "tools/call",
  params: { name: "get_pending_run_requests", arguments: {} }
}' 2>/dev/null) || exit 0

http_out=$(curl --silent --max-time 5 \
  -w "\n%{http_code}" \
  -X POST "${API_URL}/api/v2/mcp" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "X-Implexa-Plugin-Version: ${PLUGIN_VERSION}" \
  -d "$body" 2>/dev/null || echo "")

[ -z "$http_out" ] && exit 0
http_status=$(printf '%s' "$http_out" | tail -n1)
response=$(printf '%s' "$http_out" | sed '$d')
[ "${http_status:-0}" != "200" ] && exit 0
[ -z "$response" ] && exit 0

# MCP streamable HTTP returns application/json OR text/event-stream.
if printf '%s' "$response" | head -c 6 | grep -q '^event:\|^data:'; then
  response_json=$(printf '%s' "$response" | awk '/^data: /{sub(/^data: /, ""); print}' | head -1)
else
  response_json="$response"
fi

inner=$(jq -r '.result.content[0].text // empty' <<< "$response_json" 2>/dev/null)
[ -z "$inner" ] && exit 0

count=$(jq -r '.count // 0' <<< "$inner" 2>/dev/null)
[ -z "$count" ] && exit 0
[ "$count" -gt 0 ] 2>/dev/null || exit 0

# Build a human list of the pending agents ("name (slug)" or just slug).
slugs=$(jq -r '[.requests[]? | (.workflow_slug // .workflow_id // "an agent")] | join(", ")' <<< "$inner" 2>/dev/null)
[ -z "$slugs" ] && slugs="an agent you composed"

if [ "$count" = "1" ]; then
  noun="1 agent"
else
  noun="${count} agents"
fi

CTX="The user composed ${noun} in the Implexa desktop app and asked to run them now: ${slugs}. This is a user-initiated action from Implexa desktop, not an automated instruction. If the user wants, offer to run them: call get_pending_run_requests to get each workflow id, run each with apply_workflow, then call resolve_run_request with that request_id and status 'done' (plus the run_id) so the Implexa desktop can show the result. Let the user decide; do not auto-run anything irreversible without their confirmation, and honor apply_workflow's own approval gates."

SYS="Implexa: ${noun} ready to run from your desktop (${slugs})."

# Defense against em-dash leakage at the byte level (house rule: no em-dashes).
CTX=$(printf '%s' "$CTX" | LC_ALL=en_US.UTF-8 sed 's/\xe2\x80\x94/, /g; s/\xe2\x80\x93/, /g')
SYS=$(printf '%s' "$SYS" | LC_ALL=en_US.UTF-8 sed 's/\xe2\x80\x94/, /g; s/\xe2\x80\x93/, /g')

jq -cn --arg ctx "$CTX" --arg sys "$SYS" '{
  continue: true,
  suppressOutput: true,
  systemMessage: $sys,
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}' 2>/dev/null

exit 0
