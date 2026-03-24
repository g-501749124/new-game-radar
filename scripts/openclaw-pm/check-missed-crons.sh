#!/bin/bash
# check-missed-crons.sh - Linux-adapted critical cron checker
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/local.conf"

OPENCLAW_DIR="$OPENCLAW_PM_OPENCLAW_DIR"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
LOG_FILE="$OPENCLAW_PM_LOG_DIR/cron-check.log"
GATEWAY_PORT="$OPENCLAW_PM_GATEWAY_PORT"
CRITICAL_JOBS_FILE="$OPENCLAW_PM_CRITICAL_JOBS_FILE"

mkdir -p "$(dirname "$LOG_FILE")"
RUN_MISSED=false
JSON_OUTPUT=false

for arg in "$@"; do
  case $arg in
    --run) RUN_MISSED=true ;;
    --json) JSON_OUTPUT=true ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

get_token() {
  grep -oE '"token":\s*"[^"]+' "$CONFIG_FILE" | head -1 | sed 's/"token":\s*"//'
}

call_cron_api() {
  local action="$1" job_id="${2:-}"
  local token
  token=$(get_token)
  [ -n "$token" ] || { echo '{"error":"missing token"}' ; return 1; }
  local url="http://127.0.0.1:$GATEWAY_PORT/api/cron"
  local data="{\"action\":\"$action\""
  if [ -n "$job_id" ]; then
    data="${data},\"jobId\":\"$job_id\""
  fi
  data="${data}}"
  curl -s -X POST "$url" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$data" 2>/dev/null || true
}

check_job_ran_today() {
  local job_id="$1"
  local today_start
  today_start=$(date -d "today 00:00:00" +%s)000
  local runs last_run
  runs=$(call_cron_api "runs" "$job_id")
  if [ -z "$runs" ] || echo "$runs" | grep -q '"error"'; then
    echo "error"
    return
  fi
  last_run=$(echo "$runs" | python3 -c '
import sys,json
try:
  data=json.loads(sys.stdin.read())
  runs=data.get("runs", [])
  if runs:
    last=max(runs, key=lambda x: x.get("startedAtMs", 0))
    print(last.get("startedAtMs", 0))
  else:
    print(0)
except Exception:
  print(0)
' 2>/dev/null)
  if [ "$last_run" -ge "$today_start" ]; then
    echo "ok"
  else
    echo "missed"
  fi
}

trigger_job() {
  local job_id="$1"
  call_cron_api "run" "$job_id" >/dev/null 2>&1 || true
}

load_critical_jobs() {
  [ -f "$CRITICAL_JOBS_FILE" ] || return 0
  grep -v '^#' "$CRITICAL_JOBS_FILE" | grep '|' || true
}

main() {
  local missed_count=0 ok_count=0 error_count=0 missed_jobs="" results=""
  if ! curl -s "http://127.0.0.1:$GATEWAY_PORT/health" >/dev/null 2>&1; then
    $JSON_OUTPUT && echo '{"error":"gateway not running","jobs":[]}' || echo -e "${RED}✗${NC} Gateway 未运行，无法检查 cron 任务"
    exit 1
  fi
  local jobs
  jobs=$(load_critical_jobs)
  if [ -z "$jobs" ]; then
    $JSON_OUTPUT && echo '{"ok":0,"missed":0,"error":0,"jobs":[],"note":"critical jobs not configured"}' || echo -e "${YELLOW}⚠${NC} critical-jobs.txt 还没配置，暂不检查关键任务"
    exit 0
  fi
  if ! $JSON_OUTPUT; then
    echo "🕐 Cron 任务检查 ($(date '+%Y-%m-%d %H:%M'))"
    echo ""
  fi
  while IFS= read -r job_entry; do
    [ -n "$job_entry" ] || continue
    local name job_id status
    name="${job_entry%%|*}"
    job_id="${job_entry##*|}"
    status=$(check_job_ran_today "$job_id")
    case $status in
      ok)
        ((ok_count++))
        ! $JSON_OUTPUT && echo -e "${GREEN}✓${NC} $name"
        results="${results}{\"name\":\"$name\",\"jobId\":\"$job_id\",\"status\":\"ok\"},"
        ;;
      missed)
        ((missed_count++))
        missed_jobs="$missed_jobs $job_id"
        ! $JSON_OUTPUT && echo -e "${YELLOW}⚠${NC} $name - 今日未执行"
        results="${results}{\"name\":\"$name\",\"jobId\":\"$job_id\",\"status\":\"missed\"},"
        ;;
      *)
        ((error_count++))
        ! $JSON_OUTPUT && echo -e "${RED}?${NC} $name - 无法检查"
        results="${results}{\"name\":\"$name\",\"jobId\":\"$job_id\",\"status\":\"error\"},"
        ;;
    esac
  done <<< "$jobs"
  if $RUN_MISSED && [ $missed_count -gt 0 ]; then
    ! $JSON_OUTPUT && echo -e "\n🔄 补执行错过的任务..."
    for job_id in $missed_jobs; do
      trigger_job "$job_id"
      ! $JSON_OUTPUT && echo "  - 已触发: $job_id"
    done
  fi
  if $JSON_OUTPUT; then
    results="${results%,}"
    echo "{\"ok\":$ok_count,\"missed\":$missed_count,\"error\":$error_count,\"jobs\":[${results}]}"
  else
    echo ""
    if [ $missed_count -eq 0 ]; then
      echo -e "${GREEN}✓ 所有关键任务今日已执行${NC}"
    else
      echo -e "${YELLOW}⚠ $missed_count 个任务今日未执行${NC}"
      ! $RUN_MISSED && echo "  使用 --run 参数可以补执行"
    fi
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checked: ok=$ok_count missed=$missed_count error=$error_count" >> "$LOG_FILE"
  [ $missed_count -gt 0 ] && exit 1 || exit 0
}

main
