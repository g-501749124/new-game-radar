#!/bin/bash
# gateway-health-check.sh - Linux-adapted OpenClaw gateway health check
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/local.conf"

LOG_FILE="$OPENCLAW_PM_HEALTH_LOG"
OPENCLAW_DIR="$OPENCLAW_PM_OPENCLAW_DIR"
LOCK_TIMEOUT_MINUTES="$OPENCLAW_PM_LOCK_TIMEOUT_MINUTES"
LOCK_FORCE_REMOVE_MINUTES="$OPENCLAW_PM_LOCK_FORCE_REMOVE_MINUTES"
RETRY_STATE_FILE="$OPENCLAW_PM_RETRY_STATE_FILE"
TODAY_LOG="$OPENCLAW_PM_TODAY_LOG"
QUEUE_STUCK_MINUTES="$OPENCLAW_PM_QUEUE_STUCK_MINUTES"
MAX_RETRIES="$OPENCLAW_PM_MAX_RETRIES"
RETRY_INTERVAL_SECONDS="$OPENCLAW_PM_RETRY_INTERVAL_SECONDS"
GATEWAY_PORT="$OPENCLAW_PM_GATEWAY_PORT"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

get_gateway_pids() {
  ps aux | grep "[o]penclaw-gateway" | awk '{print $2}' | sort -n
}

is_gateway_running() {
  [ -n "$(get_gateway_pids)" ]
}

file_mtime_epoch() {
  stat -c %Y "$1" 2>/dev/null || echo 0
}

iso_to_epoch() {
  python3 - "$1" <<'PY'
import sys
from datetime import datetime
s=sys.argv[1].strip()
if not s:
    print(0); raise SystemExit
s=s.replace('Z','')
s=s.split('.')[0]
for fmt in ('%Y-%m-%dT%H:%M:%S','%Y-%m-%d %H:%M:%S'):
    try:
        print(int(datetime.strptime(s, fmt).timestamp()))
        raise SystemExit
    except Exception:
        pass
print(0)
PY
}

get_gateway_token() {
  grep -oE '"token":\s*"[^"]+' "$OPENCLAW_DIR/openclaw.json" | head -1 | sed 's/"token":\s*"//'
}

send_wake() {
  local text="$1"
  local token
  token=$(get_gateway_token)
  [ -n "$token" ] || { log "ERROR: Could not find gateway token"; return 1; }
  curl -s -X POST "http://127.0.0.1:${GATEWAY_PORT}/api/cron/wake" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"text\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$text"),\"mode\":\"now\"}" \
    >> "$LOG_FILE" 2>&1 || true
}

check_multiple_gateways() {
  local pids count newest
  pids=$(get_gateway_pids)
  count=$(echo "$pids" | grep -c . 2>/dev/null || echo 0)
  if [ "$count" -gt 1 ]; then
    log "WARNING: Found $count gateway processes, killing old ones"
    newest=$(echo "$pids" | tail -1)
    for pid in $pids; do
      if [ "$pid" != "$newest" ]; then
        log "Killing old gateway process: $pid"
        kill "$pid" 2>/dev/null || true
      fi
    done
    return 1
  fi
  return 0
}

check_stale_locks() {
  local fixed=0
  shopt -s nullglob
  for lock_file in "$OPENCLAW_DIR"/agents/*/sessions/*.lock; do
    local age_minutes lock_pid mtime
    mtime=$(file_mtime_epoch "$lock_file")
    [ "$mtime" -gt 0 ] || continue
    age_minutes=$(( ($(date +%s) - mtime) / 60 ))
    if [ "$age_minutes" -gt "$LOCK_TIMEOUT_MINUTES" ]; then
      lock_pid=$(grep -oE '"pid":\s*[0-9]+' "$lock_file" 2>/dev/null | grep -oE '[0-9]+' || true)
      if [ -n "$lock_pid" ]; then
        if ! ps -p "$lock_pid" >/dev/null 2>&1; then
          log "Removing stale lock file (pid $lock_pid not running): $lock_file"
          rm -f "$lock_file"
          fixed=1
        elif [ "$age_minutes" -gt "$LOCK_FORCE_REMOVE_MINUTES" ]; then
          log "Removing very old lock file (${age_minutes}min, pid $lock_pid still running): $lock_file"
          rm -f "$lock_file"
          fixed=1
        fi
      fi
    fi
  done
  return $fixed
}

check_gateway_running() {
  if ! is_gateway_running; then
    log "WARNING: Gateway not running, attempting to start"
    openclaw gateway start >> "$LOG_FILE" 2>&1 || true
    sleep 5
    if is_gateway_running; then
      log "Gateway started successfully"
      sleep 10
      send_wake "[Gateway 重启通知] Gateway 刚被健康检查脚本重启。请：1) 汇报重启情况 2) 检查之前的任务状态 3) 继续推进未完成的任务"
    else
      log "ERROR: Failed to start gateway"
      return 1
    fi
  fi
  return 0
}

check_provider_errors() {
  [ -f "$TODAY_LOG" ] || return 0
  local recent_errors last_error_line last_error_time error_epoch now_epoch age_seconds failed_lane
  recent_errors=$(grep -E "All models failed|FailoverError" "$TODAY_LOG" 2>/dev/null | tail -20 || true)
  [ -n "$recent_errors" ] || { rm -f "$RETRY_STATE_FILE"; return 0; }
  last_error_line=$(echo "$recent_errors" | tail -1)
  last_error_time=$(echo "$last_error_line" | grep -oE '"date":"[^"]+' | sed 's/"date":"//' || true)
  if [ -n "$last_error_time" ]; then
    error_epoch=$(iso_to_epoch "$last_error_time")
    now_epoch=$(date +%s)
    age_seconds=$((now_epoch - error_epoch))
    [ "$age_seconds" -le 300 ] || { rm -f "$RETRY_STATE_FILE"; return 0; }
  fi
  failed_lane=$(grep -E "lane task error.*All models failed|lane task error.*FailoverError" "$TODAY_LOG" 2>/dev/null | tail -1 | grep -oE 'lane=[^ ]+' | sed 's/lane=//' || true)
  [ -n "$failed_lane" ] || return 0
  local retry_count=0 last_retry_time=0 stored_lane now time_since_last
  if [ -f "$RETRY_STATE_FILE" ]; then
    retry_count=$(grep -oE '"count":\s*[0-9]+' "$RETRY_STATE_FILE" | grep -oE '[0-9]+' || echo 0)
    last_retry_time=$(grep -oE '"lastRetry":\s*[0-9]+' "$RETRY_STATE_FILE" | grep -oE '[0-9]+' || echo 0)
    stored_lane=$(grep -oE '"lane":"[^"]+' "$RETRY_STATE_FILE" | sed 's/"lane":"//' || true)
    [ "$stored_lane" = "$failed_lane" ] || { retry_count=0; last_retry_time=0; }
  fi
  [ "$retry_count" -lt "$MAX_RETRIES" ] || { log "Max retries reached for lane: $failed_lane"; return 0; }
  now=$(date +%s)
  time_since_last=$((now - last_retry_time))
  [ "$time_since_last" -ge "$RETRY_INTERVAL_SECONDS" ] || { log "Waiting retry interval"; return 0; }
  retry_count=$((retry_count + 1))
  echo "{\"lane\":\"$failed_lane\",\"count\":$retry_count,\"lastRetry\":$now,\"lastError\":\"$last_error_time\"}" > "$RETRY_STATE_FILE"
  log "Triggering retry $retry_count/$MAX_RETRIES for lane: $failed_lane"
  send_wake "[自动重试] Provider 错误恢复检查 (第 $retry_count 次)。失败的 session: $failed_lane"
  return 1
}

check_queue_stuck() {
  [ -f "$TODAY_LOG" ] || return 0
  local now_epoch stuck_threshold recent_log dequeue_events stuck_lanes=""
  now_epoch=$(date +%s)
  stuck_threshold=$((QUEUE_STUCK_MINUTES * 60))
  recent_log=$(tail -2000 "$TODAY_LOG" 2>/dev/null || true)
  dequeue_events=$(echo "$recent_log" | grep "lane dequeue" | grep -oE '"date":"[^"]+"|lane=[^ ]+' | paste - - | sed 's/"date":"//g' | sed 's/"//g' || true)
  while IFS=$'\t' read -r timestamp lane_info; do
    [ -n "$timestamp" ] || continue
    [ -n "$lane_info" ] || continue
    local lane event_time event_epoch age_seconds has_done done_time done_epoch
    lane=$(echo "$lane_info" | sed 's/lane=//')
    event_time="${timestamp%%.*}"
    event_epoch=$(iso_to_epoch "$event_time")
    [ "$event_epoch" -gt 0 ] || continue
    age_seconds=$((now_epoch - event_epoch))
    [ "$age_seconds" -le 600 ] || continue
    has_done=$(echo "$recent_log" | grep -E "lane task (done|error).*$lane" | grep -oE '"date":"[^"]+' | tail -1 | sed 's/"date":"//' || true)
    if [ -n "$has_done" ]; then
      done_time="${has_done%%.*}"
      done_epoch=$(iso_to_epoch "$done_time")
      [ "$done_epoch" -le "$event_epoch" ] || continue
    fi
    if [ "$age_seconds" -gt "$stuck_threshold" ]; then
      log "WARNING: Queue stuck for lane: $lane (${age_seconds}s > ${stuck_threshold}s)"
      stuck_lanes="$stuck_lanes $lane"
    fi
  done <<< "$dequeue_events"
  if [ -n "$stuck_lanes" ]; then
    log "Detected stuck queues:$stuck_lanes"
    openclaw gateway restart >> "$LOG_FILE" 2>&1 || true
    sleep 10
    send_wake "[队列卡住自动恢复] 检测到以下 session 队列卡住超过 ${QUEUE_STUCK_MINUTES} 分钟，已自动重启 Gateway：$stuck_lanes。请检查所有 session 的任务状态，继续推进未完成的任务。"
    return 1
  fi
  return 0
}

check_feishu_connection() {
  local gateway_log="$OPENCLAW_PM_GATEWAY_LOG"
  [ -f "$gateway_log" ] || return 0
  local recent_disconnect reconnect
  recent_disconnect=$(tail -100 "$gateway_log" | grep -E "abort signal received|WebSocket.*closed|connection.*lost" | tail -1 || true)
  if [ -n "$recent_disconnect" ]; then
    reconnect=$(tail -50 "$gateway_log" | grep -E "WebSocket client started" | tail -1 || true)
    if [ -z "$reconnect" ]; then
      log "WARNING: Feishu connection may be down, restarting gateway"
      openclaw gateway restart >> "$LOG_FILE" 2>&1 || true
      return 1
    fi
  fi
  return 0
}

check_stuck_thinking_sessions() {
  local fixed=0
  shopt -s nullglob
  for session_file in "$OPENCLAW_DIR"/agents/*/sessions/*.jsonl; do
    [ -f "$session_file" ] || continue
    [ -f "${session_file}.lock" ] && continue
    local is_stuck age_minutes
    is_stuck=$(tail -1 "$session_file" | python3 -c '
import sys, json
try:
    d=json.loads(sys.stdin.read().strip())
    msg=d.get("message", {})
    role=msg.get("role", "")
    content=msg.get("content", [])
    if role=="assistant":
        types=[c.get("type") for c in content if isinstance(c, dict)]
        if types==["thinking"]:
            print("stuck")
    elif role=="toolResult":
        text=" ".join(c.get("text","") for c in content if isinstance(c,dict) and c.get("type")=="text")
        if "synthetic error" in text or "missing tool result" in text:
            print("stuck")
except Exception:
    pass
' 2>/dev/null || true)
    if [ "$is_stuck" = "stuck" ]; then
      age_minutes=$(( ($(date +%s) - $(file_mtime_epoch "$session_file")) / 60 ))
      if [ "$age_minutes" -gt 5 ]; then
        log "Removing thinking-only stuck session (${age_minutes}min old): $session_file"
        rm -f "$session_file"
        fixed=$((fixed + 1))
      fi
    fi
  done
  return $fixed
}

check_session_states() {
  local script="$OPENCLAW_PM_WORKSPACE_DIR/scripts/fix-sessions.py"
  [ -f "$script" ] || return 0
  python3 "$script" >> "$LOG_FILE" 2>&1 || return $? 
  return 0
}

check_stuck_dispatch() {
  local detect_script="$OPENCLAW_PM_WORKSPACE_DIR/scripts/detect-stuck-dispatch.py"
  [ -f "$detect_script" ] || return 0
  local stuck_state_file="$OPENCLAW_DIR/stuck-dispatch-state.json"
  if [ -f "$stuck_state_file" ]; then
    local last_restart now_epoch elapsed
    last_restart=$(grep -oE '"lastRestart":\s*[0-9]+' "$stuck_state_file" | grep -oE '[0-9]+' || echo 0)
    now_epoch=$(date +%s)
    elapsed=$(( now_epoch - last_restart ))
    [ "$elapsed" -ge 1800 ] || { log "Stuck dispatch: skipping (${elapsed}s ago)"; return 0; }
  fi
  local stuck_sessions recovery_file stuck_escaped
  stuck_sessions=$(python3 "$detect_script" 2>/dev/null || true)
  [ -n "$stuck_sessions" ] || return 0
  log "WARNING: Stuck dispatch detected for sessions: $stuck_sessions"
  recovery_file=$(python3 "$OPENCLAW_PM_WORKSPACE_DIR/scripts/save-session-states.py" $stuck_sessions 2>/dev/null || true)
  echo "{\"lastRestart\":$(date +%s),\"stuckSessions\":\"$stuck_sessions\"}" > "$stuck_state_file"
  openclaw gateway restart >> "$LOG_FILE" 2>&1 || true
  sleep 10
  stuck_escaped=$(echo "$stuck_sessions" | tr '\n' ',' | sed 's/,$//')
  send_wake "[Stuck Dispatch 自动恢复] 检测到 session dispatch 卡住（消息被 dispatch 但无 LLM 调用），已自动重启 Gateway。卡住的 session：$stuck_escaped。恢复文件：$recovery_file。请读取恢复文件，用 sessions_send 主动联系卡住的 session 用户，告知消息可能未收到，请重新发送。"
  return 1
}

main() {
  log "=== Health check started ==="
  local issues=0
  check_gateway_running || ((issues++))
  check_multiple_gateways || ((issues++))
  check_stale_locks || ((issues++))
  check_stuck_thinking_sessions || ((issues++))
  check_session_states || ((issues++))
  check_stuck_dispatch || ((issues++))
  check_queue_stuck || ((issues++))
  check_provider_errors || ((issues++))
  # check_feishu_connection || ((issues++))
  if [ "$issues" -gt 0 ]; then
    log "Fixed $issues issue(s)"
  else
    log "All checks passed"
  fi
  log "=== Health check completed ==="
}

main
