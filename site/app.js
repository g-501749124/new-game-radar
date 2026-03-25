const dataUrl = './data/radar.json';

const els = {
  sampleCount: document.getElementById('sampleCount'),
  recentCount: document.getElementById('recentCount'),
  candidateCount: document.getElementById('candidateCount'),
  statusText: document.getElementById('statusText'),
  generatedAt: document.getElementById('generatedAt'),
  cardList: document.getElementById('cardList'),
  emptyState: document.getElementById('emptyState'),
  messageBox: document.getElementById('messageBox'),
  refreshBtn: document.getElementById('refreshBtn'),
  template: document.getElementById('cardTemplate'),
  topBadge: document.getElementById('topBadge'),
  topRoomCard: document.getElementById('topRoomCard'),
  topRoomEmpty: document.getElementById('topRoomEmpty'),
  topRoomTitle: document.getElementById('topRoomTitle'),
  topRoomGame: document.getElementById('topRoomGame'),
  topRoomStreamer: document.getElementById('topRoomStreamer'),
  topRoomPlatform: document.getElementById('topRoomPlatform'),
  topRoomHeat: document.getElementById('topRoomHeat'),
  topRoomId: document.getElementById('topRoomId'),
  topRoomLink: document.getElementById('topRoomLink'),
};

function formatNumber(value) {
  return new Intl.NumberFormat('zh-CN').format(value ?? 0);
}

function formatGeneratedAt(value) {
  if (!value) return '未知';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat('zh-CN', {
    dateStyle: 'medium',
    timeStyle: 'medium',
  }).format(date);
}

function chip(text) {
  const node = document.createElement('span');
  node.textContent = text;
  return node;
}

function renderTopRoom(topLiveRoom) {
  if (!topLiveRoom) {
    els.topBadge.textContent = '暂无样本';
    els.topRoomCard.classList.add('hidden');
    els.topRoomEmpty.classList.remove('hidden');
    return;
  }

  els.topBadge.textContent = '实时样本';
  els.topRoomCard.classList.remove('hidden');
  els.topRoomEmpty.classList.add('hidden');

  els.topRoomTitle.textContent = topLiveRoom.title || '暂无直播标题';
  els.topRoomGame.textContent = topLiveRoom.game || '未知游戏';
  els.topRoomStreamer.textContent = topLiveRoom.streamer || '未知主播';
  els.topRoomPlatform.textContent = topLiveRoom.platform || '未知平台';
  els.topRoomHeat.textContent = formatNumber(topLiveRoom.heat ?? 0);
  els.topRoomId.textContent = topLiveRoom.room_id || '未知';

  if (topLiveRoom.room_url) {
    els.topRoomLink.href = topLiveRoom.room_url;
    els.topRoomLink.textContent = '打开直播间';
    els.topRoomLink.style.opacity = '1';
    els.topRoomLink.style.pointerEvents = 'auto';
  } else {
    els.topRoomLink.removeAttribute('href');
    els.topRoomLink.textContent = '暂无链接';
    els.topRoomLink.style.opacity = '0.6';
    els.topRoomLink.style.pointerEvents = 'none';
  }
}

function renderCards(candidates) {
  els.cardList.innerHTML = '';
  if (!candidates.length) {
    els.emptyState.classList.remove('hidden');
    return;
  }
  els.emptyState.classList.add('hidden');
  for (const item of candidates) {
    const card = els.template.content.firstElementChild.cloneNode(true);
    card.querySelector('.game-name').textContent = item.game || '未知游戏';
    card.querySelector('.steam-name').textContent = item.steam_name || item.game || '未匹配 Steam 名称';
    card.querySelector('.score-badge').textContent = `评分 ${item.score ?? 0}`;
    card.querySelector('.release-date').textContent = item.release_date || '未知';
    card.querySelector('.platforms').textContent = (item.platforms || []).join(' / ') || '未知';
    card.querySelector('.count').textContent = `${item.count ?? 0} 个`;
    card.querySelector('.heat').textContent = formatNumber(item.total_heat ?? 0);
    card.querySelector('.title-sample').textContent = item.titles?.[0] ? `标题样本：${item.titles[0]}` : '暂无标题样本';

    const reasons = card.querySelector('.reasons');
    const streamers = card.querySelector('.streamers');
    (item.reasons || []).forEach((reason) => reasons.appendChild(chip(reason)));
    (item.streamers || []).forEach((name) => streamers.appendChild(chip(name)));

    const link = card.querySelector('.steam-link');
    if (item.appid) {
      link.href = `https://store.steampowered.com/app/${item.appid}/`;
    } else {
      link.removeAttribute('href');
      link.textContent = '暂无 Steam 页面';
      link.style.opacity = '0.6';
      link.style.pointerEvents = 'none';
    }

    els.cardList.appendChild(card);
  }
}

async function loadRadar() {
  els.statusText.textContent = '加载中…';
  try {
    const res = await fetch(`${dataUrl}?t=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    els.sampleCount.textContent = formatNumber(data.sampleCount);
    els.recentCount.textContent = formatNumber(data.recentCount);
    els.candidateCount.textContent = formatNumber((data.candidates || []).length);
    els.generatedAt.textContent = formatGeneratedAt(data.generatedAt);
    els.messageBox.textContent = data.message || '无播报内容';
    els.statusText.textContent = data.status || ((data.candidates || []).length ? '已加载' : '当前无候选新游');
    renderTopRoom(data.topLiveRoom || null);
    renderCards(data.candidates || []);
  } catch (error) {
    els.statusText.textContent = '加载失败';
    els.generatedAt.textContent = '读取失败';
    els.messageBox.textContent = `读取 ${dataUrl} 失败：${error.message}`;
    els.cardList.innerHTML = '';
    els.emptyState.classList.remove('hidden');
    renderTopRoom(null);
  }
}

els.refreshBtn.addEventListener('click', loadRadar);
loadRadar();
