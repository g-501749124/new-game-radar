#!/usr/bin/env python3
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path('/root/.openclaw/workspace')
SITE_DATA = ROOT / 'site' / 'data'
SITE_DATA.mkdir(parents=True, exist_ok=True)
TARGET = SITE_DATA / 'radar.json'

cmd = ['python3', str(ROOT / 'scripts' / 'new_game_radar.py'), '--json']
result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=True)
data = json.loads(result.stdout)
data['generatedAt'] = datetime.now(timezone.utc).astimezone().isoformat()
data['status'] = '当前无候选新游' if not data.get('candidates') else '已生成最新雷达'
TARGET.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print(str(TARGET))
