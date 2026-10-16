---
id: magpie-plugin-watch
title: Magpie 免费网关插件每日巡检
enabled: true
mode: task
schedule:
  kind: daily
  timezone: '@user.current'
  time: 08:46:00
delivery:
  - chat_id: <Muse 投递目标 chat_id>
metadata:
  presentation_locale: zh-CN
---
每日巡检 Magpie 免费网关插件（GitHub: lesnolie/magpie-free-gateways），它是 pi 备用免费模型池的上游：

1. 直接运行 `$HOME/workspace/lvsea-muse-pi/scripts/magpie-plugin-watch.sh`（脚本会拿 GitHub 最新 commit 与 `~/.config/magpie/free-gateways.hash` 比对；有更新则自动 `magpie plugin update`、重启网关并验证；无更新则静默退出）。
2. 退出码 0 = 无变化：保持沉默，不要打扰用户，不要产生任何汇报。
3. 退出码 1 = 有更新并已自动同步、验证通过：用简体中文向用户简短汇报一次：插件已更新（从 `~/workspace/logs/magpie-plugin-watch.log` 最后一行取时间和新 commit hash 前 8 位），网关与 pi 备用池验证正常。
4. 退出码 2 = 同步或验证失败：用简体中文向用户汇报失败，附上 `~/workspace/logs/magpie-plugin-watch.log` 最后约 15 行的关键信息，说明需要人工看一眼。

纪律：无变化时绝不汇报；绝不改动 pi 的主力 ling 配置（`~/.pi/agent/models.json` 的 ling 部分和 `settings.json` 的 defaultProvider/defaultModel）。

> 接入方式二选一：
> - Muse 环境：用 Muse 的 cron 工具直接导入本文件（frontmatter 即任务定义，`delivery` 里填投递目标 chat_id）。
> - 裸机环境：系统 cron / launchd / systemd timer。例（crontab -e）：
>   `46 8 * * * $HOME/workspace/lvsea-muse-pi/scripts/magpie-plugin-watch.sh`
>   注意：脚本退出码 1/2 才需要通知用户，通知通道自行接入。
