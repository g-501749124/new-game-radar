#!/usr/bin/env python3
import json
import sys
import urllib.parse
from datetime import datetime

import requests

HEADERS = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://www.bilibili.com/'
}
TREND_URL = 'https://api.bilibili.com/x/web-interface/search/square?limit=10'
SEARCH_URL = 'https://api.bilibili.com/x/web-interface/search/all/v2?keyword={keyword}'


def fetch_json(url: str):
    r = requests.get(url, headers=HEADERS, timeout=20)
    r.raise_for_status()
    return r.json()


def get_top10():
    data = fetch_json(TREND_URL)
    return data['data']['trending']['list'][:10]


def first_video_for_keyword(keyword: str):
    data = fetch_json(SEARCH_URL.format(keyword=urllib.parse.quote(keyword, safe='')))
    for block in data.get('data', {}).get('result', []):
        if block.get('result_type') == 'video':
            items = block.get('data') or []
            if not items:
                break
            v = items[0]
            title = (v.get('title') or '').replace('<em class="keyword">', '').replace('</em>', '')
            arcurl = v.get('arcurl')
            bvid = v.get('bvid')
            if not arcurl and bvid:
                arcurl = f'https://www.bilibili.com/video/{bvid}'
            return title or keyword, arcurl or ''
    return keyword, ''


def build_message():
    trends = get_top10()
    now = datetime.now().strftime('%m-%d %H:%M')
    lines = [f'B站热搜 Top 10（{now}）', '']
    for idx, item in enumerate(trends, 1):
        kw = item.get('show_name') or item.get('keyword') or f'热搜{idx}'
        heat = item.get('heat_score')
        video_title, url = first_video_for_keyword(item.get('keyword') or kw)
        lines.append(f'{idx}. {kw}')
        if heat is not None:
            lines.append(f'   热度：{heat}')
        lines.append(f'   命中视频：{video_title}')
        lines.append(f'   直链：{url or "（未找到）"}')
        lines.append('')
    return '\n'.join(lines).rstrip() + '\n'


if __name__ == '__main__':
    msg = build_message()
    if len(sys.argv) > 1 and sys.argv[1] == '--json':
        print(json.dumps({'message': msg}, ensure_ascii=False))
    else:
        print(msg, end='')
