#!/usr/bin/env python3
import json
import os
import re
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

import requests

DOUYU_HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.douyu.com/'}
HUYA_HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.huya.com/'}
BILI_HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://live.bilibili.com/'}
STEAM_HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://store.steampowered.com/'}

DOUYU_URL = 'https://www.douyu.com/gapi/rkc/directory/mixListV1/0_0/{page}'
HUYA_URL = 'https://www.huya.com/cache.php?m=LiveList&do=getLiveListByPage&gameId=0&tagAll=0&page={page}'
BILI_URL = 'https://api.live.bilibili.com/xlive/web-interface/v1/index/getList?platform=web&parent_area_id=0&area_id=0&page={page}'
STEAM_SEARCH_URL = 'https://store.steampowered.com/search/suggest?term={term}&f=games&cc=CN&l=schinese'
STEAM_APP_URL = 'https://store.steampowered.com/api/appdetails?appids={appid}&l=schinese&cc=cn'

DATA_DIR = '/root/.openclaw/workspace/data/new_game_radar'
CACHE_PATH = os.path.join(DATA_DIR, 'steam_matches.json')

BORING_GAMES = {
    '英雄联盟', '王者荣耀', '无畏契约', '穿越火线', 'CF', '地下城与勇士', 'DNF',
    '三角洲行动', '绝地求生', 'PUBG', 'CS2', '反恐精英2', '原神', '炉石传说',
    '主机游戏', '主机其他游戏', '娱乐天地', '户外', '体育', '棋牌娱乐', '星秀',
    'QQ飞车', '和平精英', '暗区突围', '梦幻西游', 'DOTA2', '魔兽世界', 'APEX英雄',
    '云顶之弈', '金铲铲之战', '天天象棋', '天天吃鸡', '交友', '热门游戏', '原创', '二次元',
    '科技', '欢乐麻将', '颜值', '电台', '虚拟主播', '娱乐', '单机热游', '网游竞技',
    '三国杀', '永劫无间', '火影忍者', '一起看'
}

NON_GAME_PATTERNS = [
    '交友', '原创', '二次元', '颜值', '娱乐', '电台', '户外', '体育', '星秀', '棋牌',
    '美女', '装机', '科技', '热点', '聊天', '陪伴', '相亲', '音乐', '舞蹈', '虚拟', '一起看'
]

NEWISH_KEYWORDS = [
    'demo', '试玩', '首发', '新游', '新品', '上线', '发售', '测试', '公测', '封测',
    '抢先体验', 'ea', '体验版', 'steam新品', '新作', '刚出', '今天上线', '新版本', '首测'
]


def fetch_json(url, headers, timeout=20):
    r = requests.get(url, headers=headers, timeout=timeout)
    r.raise_for_status()
    return r.json()


def fetch_text(url, headers, timeout=20):
    r = requests.get(url, headers=headers, timeout=timeout)
    r.raise_for_status()
    return r.text


def clean_name(name: str) -> str:
    name = (name or '').strip()
    name = re.sub(r'\s+', '', name)
    aliases = {
        'LOL': '英雄联盟', 'lol': '英雄联盟', 'LOL云顶之弈': '云顶之弈', 'lol云顶之弈': '云顶之弈',
        '瓦': '无畏契约', '瓦罗兰特': '无畏契约', 'PUBG': '绝地求生', 'pubg': '绝地求生',
        'CSGO': 'CS2', 'csgo': 'CS2'
    }
    return aliases.get(name, name)


def is_probably_game(name: str) -> bool:
    if not name:
        return False
    if name in BORING_GAMES:
        return False
    lower = name.lower()
    if any(p.lower() in lower for p in NON_GAME_PATTERNS):
        return False
    return True


def fetch_douyu_pages(pages=3):
    out = []
    for p in range(1, pages + 1):
        data = fetch_json(DOUYU_URL.format(page=p), DOUYU_HEADERS)
        for item in data.get('data', {}).get('rl', []):
            game = clean_name(item.get('c2name') or item.get('c2name_display') or '')
            if not is_probably_game(game):
                continue
            out.append({
                'platform': '斗鱼', 'game': game, 'streamer': item.get('nn') or '',
                'title': item.get('rn') or '', 'heat': int(item.get('ol') or 0),
            })
    return out


def fetch_huya_pages(pages=3):
    out = []
    for p in range(1, pages + 1):
        data = fetch_json(HUYA_URL.format(page=p), HUYA_HEADERS)
        for item in data.get('data', {}).get('datas', []):
            game = clean_name(item.get('gameFullName') or '')
            if not is_probably_game(game):
                continue
            try:
                heat = int(float(item.get('totalCount') or 0))
            except Exception:
                heat = 0
            out.append({
                'platform': '虎牙', 'game': game, 'streamer': item.get('nick') or '',
                'title': item.get('introduction') or item.get('roomName') or '', 'heat': heat,
            })
    return out


def fetch_bili_pages(pages=2):
    out = []
    for p in range(1, pages + 1):
        data = fetch_json(BILI_URL.format(page=p), BILI_HEADERS)
        for item in data.get('data', {}).get('room_list', []):
            game = clean_name(item.get('area_name') or '')
            if not is_probably_game(game):
                continue
            out.append({
                'platform': 'B站直播', 'game': game, 'streamer': item.get('uname') or '',
                'title': item.get('title') or '', 'heat': int(item.get('online') or 0),
            })
    return out


def load_cache():
    if not os.path.exists(CACHE_PATH):
        return {}
    try:
        with open(CACHE_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}


def save_cache(cache):
    with open(CACHE_PATH, 'w', encoding='utf-8') as f:
        json.dump(cache, f, ensure_ascii=False, indent=2)


def parse_release_date(date_text: str):
    if not date_text:
        return None
    text = date_text.strip()
    for fmt in ('%Y 年 %m 月 %d 日', '%Y年%m月%d日', '%Y 年%m 月%d 日', '%Y-%m-%d', '%Y/%m/%d'):
        try:
            return datetime.strptime(text, fmt).date()
        except Exception:
            pass
    m = re.search(r'(\d{4})[年/-](\d{1,2})[月/-](\d{1,2})', text)
    if m:
        y, mo, d = map(int, m.groups())
        try:
            from datetime import date
            return date(y, mo, d)
        except Exception:
            return None
    return None


def steam_search_candidates(name: str):
    url = STEAM_SEARCH_URL.format(term=quote(name))
    html = fetch_text(url, STEAM_HEADERS, timeout=20)
    matches = re.findall(r'data-ds-appid="(\d+)".*?<div class="match_name">(.*?)</div>', html, re.S)
    out = []
    for appid, title in matches[:5]:
        clean_title = re.sub('<.*?>', '', title).strip()
        out.append((appid, clean_title))
    return out


def steam_app_details(appid: str):
    data = fetch_json(STEAM_APP_URL.format(appid=appid), STEAM_HEADERS, timeout=20)
    obj = data.get(str(appid), {})
    if not obj.get('success'):
        return None
    info = obj.get('data') or {}
    rd = info.get('release_date') or {}
    return {
        'appid': appid,
        'name': info.get('name') or '',
        'release_date': rd.get('date') or '',
        'coming_soon': bool(rd.get('coming_soon')),
        'type': info.get('type') or '',
    }


def is_recent_release(date_text: str, days=30):
    d = parse_release_date(date_text)
    if not d:
        return False
    now_date = datetime.now().date()
    delta = (now_date - d).days
    return 0 <= delta <= days


def resolve_recent_steam_game(name: str, cache: dict):
    if name in cache:
        return cache[name]
    result = {'matched': False, 'game': name}
    try:
        cands = steam_search_candidates(name)
        for appid, cand_name in cands:
            details = steam_app_details(appid)
            if not details or details.get('type') != 'game':
                continue
            rel = details.get('release_date') or ''
            if is_recent_release(rel, 30):
                result = {
                    'matched': True,
                    'game': name,
                    'steam_name': details['name'],
                    'appid': appid,
                    'release_date': rel,
                }
                break
        if not result['matched']:
            result['checkedAt'] = int(time.time())
    except Exception as e:
        result['error'] = str(e)
    cache[name] = result
    return result


def score_entry(game, entries):
    score = 0
    reasons = []
    platforms = sorted({e['platform'] for e in entries})
    streamers, sample_titles = [], []
    total_heat = sum(e['heat'] for e in entries)
    score += 3
    reasons.append('Steam 校验为近 30 天发售新游戏')
    if len(platforms) >= 2:
        score += 3
        reasons.append('跨平台同时出现')
    else:
        score += 1
    if len(entries) >= 3:
        score += 2
        reasons.append('同时间段出现多个直播间')
    elif len(entries) == 2:
        score += 1
    if total_heat >= 1500000:
        score += 2
        reasons.append('综合热度较高')
    elif total_heat >= 300000:
        score += 1
    keyword_hits = 0
    for e in entries:
        if e['streamer'] and e['streamer'] not in streamers:
            streamers.append(e['streamer'])
        if e['title'] and e['title'] not in sample_titles:
            sample_titles.append(e['title'])
        lower = (e['title'] or '').lower()
        if any(k in lower for k in NEWISH_KEYWORDS):
            keyword_hits += 1
    if keyword_hits:
        score += min(3, keyword_hits)
        reasons.append('标题含试玩/首发/测试等新游信号')
    return {
        'game': game, 'score': score, 'platforms': platforms, 'streamers': streamers[:4],
        'titles': sample_titles[:3], 'count': len(entries), 'total_heat': total_heat, 'reasons': reasons,
    }


def build_radar():
    rows = fetch_douyu_pages(3) + fetch_huya_pages(3) + fetch_bili_pages(2)
    grouped = defaultdict(list)
    for row in rows:
        grouped[row['game']].append(row)
    cache = load_cache()
    recent = {}
    for game in sorted(grouped.keys()):
        resolved = resolve_recent_steam_game(game, cache)
        if resolved.get('matched'):
            recent[game] = resolved
    save_cache(cache)
    candidates = []
    for game, steam_info in recent.items():
        item = score_entry(game, grouped[game])
        item['steam_name'] = steam_info.get('steam_name')
        item['release_date'] = steam_info.get('release_date')
        item['appid'] = steam_info.get('appid')
        candidates.append(item)
    candidates.sort(key=lambda x: (-x['score'], -x['total_heat'], -x['count'], x['game']))
    return candidates, rows, recent


def format_text(candidates):
    now = datetime.now().strftime('%m-%d %H:%M')
    lines = [f'主播新游雷达（{now}）', '']
    if not candidates:
        lines.append('这轮没匹配到“近30天发售且正在直播平台开播”的新游戏。')
        return '\n'.join(lines) + '\n'
    for idx, item in enumerate(candidates[:10], 1):
        lines.append(f'{idx}. {item["game"]} 〔分数 {item["score"]}〕')
        lines.append(f'   Steam：{item.get("steam_name") or item["game"]} / 发售：{item.get("release_date") or "未知"}')
        lines.append(f'   平台：{" / ".join(item["platforms"])}')
        lines.append(f'   直播间样本：{item["count"]} 个  综合热度：{item["total_heat"]}')
        if item['streamers']:
            lines.append(f'   主播：{"、".join(item["streamers"])}')
        if item['reasons']:
            lines.append(f'   信号：{"；".join(item["reasons"])}')
        if item['titles']:
            lines.append(f'   标题样本：{item["titles"][0]}')
        lines.append('')
    return '\n'.join(lines).rstrip() + '\n'


if __name__ == '__main__':
    candidates, rows, recent = build_radar()
    if len(sys.argv) > 1 and sys.argv[1] == '--json':
        print(json.dumps({'message': format_text(candidates), 'candidates': candidates, 'sampleCount': len(rows), 'recentCount': len(recent)}, ensure_ascii=False))
    else:
        print(format_text(candidates), end='')
