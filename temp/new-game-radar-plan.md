# new-game-radar plan

## 目标
- 提供 new-game-radar 网页端
- 让页面可通过 80 端口访问
- 页面展示一个可验证的实时内容：当前平台播放游戏观众最多的直播间
- 提供该直播间直达链接
- 页面 UI 要更好看、布局更合理，不只是功能可用
- 完成后提交并推送 GitHub

## 当前状态
- 数据脚本：`scripts/new_game_radar.py`
- 仓库根目录：`/root/.openclaw/workspace`
- 自动播报：已停用高频噪音模式
- 自动驱动方式：计划文件 + 2 分钟低频恢复
- 网页原型：`site/index.html`、`site/app.js`、`site/styles.css` 已存在并可工作
- 站点数据：`scripts/generate_new_game_radar_site_data.py` 可生成 `site/data/radar.json`
- 服务状态：80 端口已有 `python3 -m http.server 80 --directory /root/.openclaw/workspace/site` 在运行，首页与 JSON 均可访问

## Phases
1. 跑通数据脚本并确认输出/耗时
2. 新增“当前平台播放游戏观众最多的直播间 + 直达链接”数据提取
3. 创建美观、布局合理的 `site/` 网页端原型
4. 提供服务端或静态刷新机制
5. 接到 80 端口并验证可访问
6. git commit + push

## 当前步骤
- Phase 6：处理 `site/` 被忽略的提交问题，然后创建提交并推送

## 已完成
- 确认项目根目录与主脚本位置
- 修正项目状态统计口径，避免把整个 workspace 误算进项目变更
- `scripts/new_game_radar.py --json` 已跑通，样本数约 30，输出结构已确认可消费
- 已新增 `topLiveRoom` 输出，包含平台、游戏、主播、标题、热度、直达链接
- 已确认 `site/` 页面骨架完成：首页含 hero 统计、最高热度直播间卡片、新游雷达卡片、原始播报区
- 已确认 `site/app.js` 能消费 `site/data/radar.json`，并渲染 `topLiveRoom` 与候选列表
- 已通过 `scripts/generate_new_game_radar_site_data.py` / 脚本直出方式生成最新 `site/data/radar.json`
- 已验证 8000 端口现有静态服务可访问：`/` 返回 200，`/data/radar.json` 返回 200
- 已确认 80 端口已接入 `site/`：`http://127.0.0.1/` 返回 200，`http://127.0.0.1/data/radar.json` 可解析，当前最高热度直播间链接为 `https://www.douyu.com/10362982`
- 已核对 git 状态：本任务待提交改动仅剩 `data/new_game_radar/steam_matches.json` 与 `site/data/radar.json`，其余核心网页与脚本文件已在历史提交中
- 已确认远端 `origin` 指向 `https://github.com/g-501749124/new-game-radar.git`，当前分支为 `main`
- 已确认普通 `git add` 仍会被 `.gitignore` 拦截，`site/data/radar.json` 需要继续用强制添加或调整 ignore 规则

## 下一步
- 用 `git add -f` 纳入 `site/data/radar.json`
- 完成 commit
- 推送到 GitHub
- 推送后记录提交号并结束任务

## 阻塞
- 无（可用 `git add -f` 继续）

## 验收标准
- 页面能明显看到当前最高热度直播间
- 可点击直达链接
- 页面视觉上不是简陋白板，具备清晰层级与卡片布局
- 后续能通过 80 端口访问

## Checkpoint
- 最近项目提交：`0d03923` Add new-game-radar web dashboard
