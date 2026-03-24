#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/local.conf"

REPO_DIR="$OPENCLAW_PM_WORKSPACE_DIR"
REPORT_JSON=false
if [[ "${1:-}" == "--json" ]]; then REPORT_JSON=true; fi

cd "$REPO_DIR"
last_commit=$(git log -1 --pretty='%h %s' 2>/dev/null || echo 'none')
last_commit_time=$(git log -1 --pretty='%ci' 2>/dev/null || echo 'unknown')
status_short=$(git status --short 2>/dev/null || true)
changed_count=$(printf '%s\n' "$status_short" | sed '/^$/d' | wc -l | tr -d ' ')
site_dir="$REPO_DIR/site"
web_ready=false
if [[ -f "$site_dir/index.html" || -f "$site_dir/server.js" || -f "$site_dir/package.json" ]]; then
  web_ready=true
fi
radar_script=false
if [[ -f "$REPO_DIR/scripts/new_game_radar.py" ]]; then
  radar_script=true
fi

if $REPORT_JSON; then
  python3 -c 'import json,sys; print(json.dumps({"project":sys.argv[1],"last_commit":sys.argv[2],"last_commit_time":sys.argv[3],"changed_count":int(sys.argv[4]),"web_ready":sys.argv[5]=="true","radar_script":sys.argv[6]=="true"}, ensure_ascii=False))' \
    "new-game-radar" "$last_commit" "$last_commit_time" "$changed_count" "$web_ready" "$radar_script"
else
  echo "项目: new-game-radar"
  echo "最近提交: $last_commit"
  echo "提交时间: $last_commit_time"
  echo "未提交变更数: $changed_count"
  echo "Web 目录是否就绪: $web_ready"
  echo "雷达脚本是否存在: $radar_script"
fi
