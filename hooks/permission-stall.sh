#!/usr/bin/env bash
# Implexa permission-stall hook.
#
# When an Implexa AGENT run pauses on a tool-permission prompt (e.g. an unattended
# render stalls on Bash because shell access was not pre-granted), this hook pings
# the backend so the owner gets an email to approve it (open Claude Code / the app)
# or grant it once on the dashboard. Closes the "agent is waiting for you" loop.
#
# Registered on BOTH the PermissionRequest event (carries tool_name) and the
# Notification event (notification_type=permission_prompt; no tool_name) so it
# fires regardless of which the runtime emits.
#
# SCOPED to Implexa runs: it only pings when the recent transcript shows an Implexa
# agent run, so a normal interactive Claude Code permission prompt does NOT notify.
#
# Required env (set by install-user-hooks.sh):
#   IMPLEXA_API_KEY   imp_live_... key (identifies the user server-side)
#   IMPLEXA_API_URL   optional, defaults to https://core.implexa.ai
#
# Non-blocking + silent. Any failure / missing dep / non-Implexa context exits 0
# with NO model-visible output and NEVER affects the permission decision.

set -o pipefail

API_KEY="${IMPLEXA_API_KEY:-}"
API_URL="${IMPLEXA_API_URL:-https://core.implexa.ai}"

[ -z "$API_KEY" ] && exit 0
command -v jq   >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

payload=$(cat 2>/dev/null || echo '')
[ -z "$payload" ] && exit 0

event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)
ntype=$(printf '%s' "$payload" | jq -r '.notification_type // empty' 2>/dev/null)
tool=$(printf '%s'  "$payload" | jq -r '.tool_name // empty' 2>/dev/null)

# On a Notification event, only act on a permission prompt (skip idle/other types).
if [ "$event" = "Notification" ] && [ -n "$ntype" ] && [ "$ntype" != "permission_prompt" ]; then
  exit 0
fi

# Scope to Implexa runs: only notify when the recent transcript shows an Implexa
# agent run (a scheduled run, an apply_workflow, or any implexa MCP call). This
# keeps a normal interactive Claude Code permission prompt from emailing the user.
tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$tp" ] && [ -f "$tp" ]; then
  # 800 lines, not 120: a stall can surface inside a SUBAGENT (e.g. a debate
  # persona spawned via Task) long after the implexa markers scrolled past the
  # short window - that miss is exactly how the founder watched a stalled
  # boardroom run with no email. Extra markers cover the scheduled-run wrapper.
  tail -n 800 "$tp" 2>/dev/null | grep -qiE 'implexa:run-scheduled|apply_workflow|mcp__implexa|mcp__plugin_implexa|get_scheduled_skill_payload|record_scheduled_run|record_run_start|orchestrate_skills' || exit 0
else
  exit 0  # no transcript -> cannot confirm an Implexa run -> stay quiet
fi

# Debounce: at most one ping per tool per 5 minutes (the prompt can re-fire).
key="${tool:-perm}"
STAMP="${TMPDIR:-/tmp}/implexa-permstall-${key//[^a-zA-Z0-9]/_}.ts"
now=$(date +%s 2>/dev/null || echo 0)
if [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  [ $(( now - last )) -lt 300 ] 2>/dev/null && exit 0
fi
printf '%s' "$now" > "$STAMP" 2>/dev/null || true

body=$(jq -nc --arg t "$tool" '{toolName:$t}' 2>/dev/null) || exit 0
curl --silent --max-time 4 -X POST "${API_URL}/api/v2/runs/permission-stall" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$body" >/dev/null 2>&1 || true

exit 0
