#!/bin/bash
# heartbeat-check.sh - Linux-adapted heartbeat helper
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/local.conf"
WORKSPACE_DIR="$OPENCLAW_PM_WORKSPACE_DIR"
MEMORY_DIR="$WORKSPACE_DIR/memory"
TODAY=$(date +%Y-%m-%d)
MEMORY_FILE="$MEMORY_DIR/$TODAY.md"
OUTPUT_FORMAT="text"
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --json) OUTPUT_FORMAT="json"; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

JSON_OUTPUT='{"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","checks":{}}'

add_json_result() {
  local check_name=$1 status=$2 message=$3
  JSON_OUTPUT=$(echo "$JSON_OUTPUT" | jq --arg name "$check_name" --arg status "$status" --arg msg "$message" '.checks[$name] = {"status": $status, "message": $msg}')
}

print_header() {
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}💓 Heartbeat Check - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
  fi
}

check_context_health() {
  [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "${BLUE}[1/3] Context Health${NC}"; echo -e "  ${YELLOW}⚠${NC}  需要通过 session_status tool 检查\n"; }
  add_json_result "context_health" "pending" "需要通过 session_status tool 检查"
}

check_in_progress_tasks() {
  [[ "$OUTPUT_FORMAT" == "text" ]] && echo -e "${BLUE}[2/3] 进行中任务${NC}"
  if [[ ! -f "$MEMORY_FILE" ]]; then
    [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "  ${GREEN}✓${NC}  今日 memory 文件不存在，无进行中任务\n"; }
    add_json_result "in_progress_tasks" "ok" "今日 memory 文件不存在，无进行中任务"
    return 0
  fi
  local in_progress_section
  in_progress_section=$(sed -n '/^## In Progress/,/^##/p' "$MEMORY_FILE" | grep -v '^##' || true)
  if [[ -z "$in_progress_section" ]] || echo "$in_progress_section" | grep -q '（无）'; then
    [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "  ${GREEN}✓${NC}  无进行中任务\n"; }
    add_json_result "in_progress_tasks" "ok" "无进行中任务"
    return 0
  fi
  local tasks_need_report=() tasks_found=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]](.+) ]]; then
      local task_name="${BASH_REMATCH[1]}" last_report now_total report_total diff
      tasks_found=true
      last_report=$(echo "$in_progress_section" | grep -A 5 "### $task_name" | grep '上次汇报' | sed 's/.*上次汇报：//' | sed 's/[[:space:]].*//' || true)
      if [[ -n "$last_report" ]]; then
        now_total=$((10#$(date +%H) * 60 + 10#$(date +%M)))
        report_total=$((10#$(echo "$last_report" | cut -d: -f1) * 60 + 10#$(echo "$last_report" | cut -d: -f2)))
        diff=$((now_total - report_total))
        if [[ $diff -gt 30 ]]; then
          tasks_need_report+=("$task_name (${diff}分钟未汇报)")
        fi
      fi
    fi
  done <<< "$in_progress_section"
  if [[ ${#tasks_need_report[@]} -gt 0 ]]; then
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
      echo -e "  ${YELLOW}⚠${NC}  发现需要汇报的任务："
      for task in "${tasks_need_report[@]}"; do echo -e "     - $task"; done
      echo
    fi
    add_json_result "in_progress_tasks" "warning" "$(IFS=,; echo "${tasks_need_report[*]}")"
    return 1
  elif [[ "$tasks_found" == true ]]; then
    [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "  ${GREEN}✓${NC}  进行中任务状态正常\n"; }
    add_json_result "in_progress_tasks" "ok" "任务状态正常"
  else
    [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "  ${GREEN}✓${NC}  无进行中任务\n"; }
    add_json_result "in_progress_tasks" "ok" "无进行中任务"
  fi
}

check_cron_tasks() {
  [[ "$OUTPUT_FORMAT" == "text" ]] && echo -e "${BLUE}[3/3] Cron 任务${NC}"
  local cron_check_script="$SCRIPT_DIR/check-missed-crons.sh"
  if [[ ! -f "$cron_check_script" ]]; then
    [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "  ${RED}✗${NC}  check-missed-crons.sh 不存在\n"; }
    add_json_result "cron_tasks" "error" "check-missed-crons.sh 不存在"
    return 1
  fi
  local cron_result
  cron_result=$("$cron_check_script" --json 2>&1 || true)
  if echo "$cron_result" | jq -e . >/dev/null 2>&1; then
    local missed_count note
    missed_count=$(echo "$cron_result" | jq -r '.missed // 0')
    note=$(echo "$cron_result" | jq -r '.note // empty')
    if [[ -n "$note" ]]; then
      [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "  ${YELLOW}⚠${NC}  $note\n"; }
      add_json_result "cron_tasks" "pending" "$note"
      return 0
    elif [[ "$missed_count" -eq 0 ]]; then
      [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "  ${GREEN}✓${NC}  所有关键任务已执行\n"; }
      add_json_result "cron_tasks" "ok" "所有关键任务已执行"
      return 0
    else
      local missed_tasks
      missed_tasks=$(echo "$cron_result" | jq -r '.jobs[] | select(.status=="missed") | .name' | tr '\n' ',' | sed 's/,$//')
      [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "  ${YELLOW}⚠${NC}  未执行任务：$missed_tasks\n"; }
      add_json_result "cron_tasks" "warning" "未执行: $missed_tasks"
      return 1
    fi
  fi
  [[ "$OUTPUT_FORMAT" == "text" ]] && { echo -e "  ${RED}✗${NC}  无法检查 Cron 任务\n"; }
  add_json_result "cron_tasks" "error" "无法检查 Cron 任务"
  return 1
}

main() {
  print_header
  local exit_code=0
  check_context_health || exit_code=1
  check_in_progress_tasks || exit_code=1
  check_cron_tasks || exit_code=1
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    echo "$JSON_OUTPUT" | jq '.'
  else
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [[ $exit_code -eq 0 ]]; then
      echo -e "${GREEN}✓ Heartbeat 检查通过${NC}"
    else
      echo -e "${YELLOW}⚠ Heartbeat 检查发现问题${NC}"
    fi
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  fi
  exit $exit_code
}

main
