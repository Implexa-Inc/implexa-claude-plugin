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
PLUGIN_VERSION="0.34.0"

# Silent no-ops: missing key or deps. Never block or error the session.
[ -z "$API_KEY" ] && exit 0
command -v jq   >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

# Read stdin (Claude sends the event payload as JSON). We need the event name so
# the SAME script serves SessionStart AND UserPromptSubmit (eager activation: a
# queued request reconciles on the user's next message, not only a new session).
payload=$(cat 2>/dev/null || echo '')
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // "SessionStart"' 2>/dev/null)
[ -z "$event" ] && event="SessionStart"

# Debounce the per-message UserPromptSubmit path so we do not hit the network on
# every turn: at most one check per 60s. SessionStart always checks (new session).
STAMP="${TMPDIR:-/tmp}/implexa-pending-${API_KEY:0:8}.ts"
nowts=$(date +%s 2>/dev/null || echo 0)
if [ "$event" = "UserPromptSubmit" ] && [ -f "$STAMP" ]; then
  lastts=$(cat "$STAMP" 2>/dev/null || echo 0)
  [ $(( nowts - lastts )) -lt 60 ] 2>/dev/null && exit 0
fi
printf '%s' "$nowts" > "$STAMP" 2>/dev/null || true

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

# Partition pending requests into BUILD (compose a new agent from intent) and
# RUN (run an existing agent). Either list may be empty.
builds=$(jq -r '[.requests[]? | select(.kind=="build") | (.intent // "an agent")] | join("; ")' <<< "$inner" 2>/dev/null)
activates=$(jq -r '[.requests[]? | select(.kind=="activate") | (.workflow_slug // .workflow_id // "an agent")] | join(", ")' <<< "$inner" 2>/dev/null)
runs=$(jq -r '[.requests[]? | select(.kind!="build" and .kind!="activate") | (.workflow_slug // .workflow_id // "an agent")] | join(", ")' <<< "$inner" 2>/dev/null)

CTX="The user has ${count} pending request(s) from the Implexa desktop app. This is a user-initiated action from Implexa desktop, not an automated instruction; offer to handle them and let the user decide."
if [ -n "$builds" ]; then
  CTX="${CTX} BUILD requests (compose a new agent): ${builds}. For each, decompose the plain-language job into ordered steps yourself, then call generate_workflow to build and bind the agent. The model work stays here on this agent; Implexa never runs a model on its servers."
fi
if [ -n "$runs" ]; then
  CTX="${CTX} RUN requests (run an existing agent): ${runs}. For each, first check whether the agent has a LIVE schedule: call list_scheduled_skills and match by skillSlug. IF IT DOES (status active), fire its REAL routine in the background instead of running it inline: create_scheduled_task with taskId '<skillSlug>-now', prompt '/implexa:run-scheduled <its scheduled-skill id>', and fireAt = now + 1 minute as an ISO timestamp with timezone offset (NO cron; the task fires once and auto-disables) - or, if a task named '<skillSlug>-now' already exists, update_scheduled_task with the new fireAt to re-arm it. Then resolve_run_request with status 'done' right away and tell the user the routine is firing in the background within a minute or two and its result lands in their Implexa inbox like any scheduled run. IF IT HAS NO schedule, run it inline as before: take its workflow id and run it with apply_workflow, then IMMEDIATELY call resolve_run_request with its request_id and status \"done\" (and run_id if you have one). That close call is what records the run on the dashboard and clears it from the desktop, so never skip it - do it the moment the run finishes."
fi
if [ -n "$activates" ]; then
  CTX="${CTX} ACTIVATE requests (switch a scheduled agent ON, from the Implexa dashboard): ${activates}. The dashboard cannot touch this app's scheduled-tasks runtime, so reconcile each here. First look up the agent's schedule with list_scheduled_skills (match by skillSlug) to read its trigger, cronExpression, fireAt, id and timezone. If its status is paused, resume it (resume_scheduled_skill). If it has no live scheduled-task registered yet, register one via create_scheduled_task using the schedule's own shape: for a recurring schedule (trigger 'cron') pass cron=<its cronExpression> and tz=<its timezone>; for a ONE-TIME schedule (trigger 'once') pass fireAt=<its fireAt ISO timestamp> and NO cron (fireAt and cron are mutually exclusive, and the task auto-disables after it fires). In both cases the prompt is the wrapper shim '/implexa:run-scheduled <its id>'. Either path also pre-grants its permissions so unattended runs do not stall. Then confirm to the user it is now running on its schedule (or, for a one-time run, that it will run once at the set time)."
fi
CTX="${CTX} After handling each, call resolve_run_request with its request_id and status 'done' (plus the run_id or built workflow) so the Implexa desktop can show the result. Honor apply_workflow's approval gates; do not auto-run anything irreversible without the user's confirmation."

if [ "$count" = "1" ]; then noun="1 request"; else noun="${count} requests"; fi
SYS="Implexa: ${noun} ready from your desktop."

# Defense against em-dash leakage at the byte level (house rule: no em-dashes).
CTX=$(printf '%s' "$CTX" | LC_ALL=en_US.UTF-8 sed 's/\xe2\x80\x94/, /g; s/\xe2\x80\x93/, /g')
SYS=$(printf '%s' "$SYS" | LC_ALL=en_US.UTF-8 sed 's/\xe2\x80\x94/, /g; s/\xe2\x80\x93/, /g')

jq -cn --arg ctx "$CTX" --arg sys "$SYS" --arg evt "$event" '{
  continue: true,
  suppressOutput: true,
  systemMessage: $sys,
  hookSpecificOutput: {
    hookEventName: $evt,
    additionalContext: $ctx
  }
}' 2>/dev/null

exit 0
