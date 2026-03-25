# new-game-radar plan

## 目标
- 提供 new-game-radar 网页端
- 让页面可通过 80 端口访问
- 页面展示一个可验证的实时内容：当前平台播放游戏观众最多的直播间
- 完成后提交并推送 GitHub

## 当前状态
- 数据脚本：`scripts/new_game_radar.py`
- 仓库根目录：`/root/.openclaw/workspace`
- 自动播报：已停用高频噪音模式
- 自动驱动方式：计划文件 + 2 分钟低频恢复
- 脚本已扩展 `topLiveRoom` 输出，当前样本可返回平台/游戏/主播/标题/热度/房间链接
- 网页端原型已落地在 `site/`，包含 `index.html` / `styles.css` / `app.js`
- 站点数据生成脚本：`scripts/generate_new_game_radar_site_data.py`
- 已验证 80 端口正在提供 `site/`，可直接访问首页和 `/data/radar.json`

## Phases
1. 跑通数据脚本并确认输出/耗时
2. 新增“当前平台播放游戏观众最多的直播间”数据提取
3. 创建 `site/` 网页端原型
4. 提供服务端或静态刷新机制
5. 接到 80 端口并验证可访问
6. git commit + push

## 当前步骤
- Phase 6：解决 `site/` 被 .gitignore 忽略的问题，然后提交并推送 GitHub

## 已完成
- 确认项目根目录与主脚本位置
- 修正项目状态统计口径，避免把整个 workspace 误算进项目变更
- `scripts/new_game_radar.py --json` 已跑通，样本数约 31，输出结构已确认可消费
- 驱动方式已改成计划文件驱动
- 已在抓取结果中提取全平台最高热度直播间 `topLiveRoom`
- 当前样本验证：斗鱼 / 明日方舟：终末地 / 龙四爷攻略组 / 热度 1607548
- 已创建 `site/` 网页端原型并渲染 `topLiveRoom`、候选新游卡片、原始播报、刷新时间
- 已新增 `scripts/generate_new_game_radar_site_data.py` 用于刷新 `site/data/radar.json`
- 已验证 `http://127.0.0.1/` 与 `http://127.0.0.1/data/radar.json` 可访问，当前 80 端口服务正常
- 已确认待提交变更集中在 `scripts/new_game_radar.py`、`site/`、计划文件
- 已发现当前阻塞：`site/` 被 .gitignore 忽略，普通 `git add` 无法纳入提交

## 下一步
- 查明是哪条 ignore 规则命中 `site/`
- 选择最小改动方案（`git add -f` 或调整 ignore）
- git commit
- push 到 GitHub

## 阻塞
- `site/` 被 .gitignore 忽略，需要先处理再提交

## Checkpoint
- 最近项目提交：`d77c462` Configure project status monitoring for openclaw-pm
