---
id: freetoken-bots-daily-scan
title: FreeToken-Bots 每日免费模型扫描
enabled: true
owner: goal:openrouter-free-model-watch
mode: task
schedule:
  kind: daily
  timezone: '@user.current'
  time: 08:00:00
delivery:
  - chat_id: <Muse 投递目标 chat_id>
metadata:
  presentation_locale: zh-CN
---
运行 FreeToken-Bots 的每日免费模型扫描（先快照、后扫描，保证每次可完整对比）：
1. 先存快照：radar.py 的 scan 会直接覆盖 ~/.pi/agent/freetoken-bots.json，导致上次完整名单丢失。扫描前先从该文件取出 free_ids 数组，写入 $HOME/workspace/goals/openrouter-free-model-watch/hidden_files/freetoken-free-ids-<今天日期 YYYY-MM-DD>.json（纯数组格式）。若 state 文件不存在，跳过快照继续。
2. 再执行 `python3 $HOME/workspace/skills/freetoken-bots/scripts/radar.py scan`，然后 `python3 $HOME/workspace/skills/freetoken-bots/scripts/radar.py status` 看结果。
3. 对比：本次 free_ids 与步骤 1 的快照逐项 diff，算出新增 / 下线；是否被改价（不再免费）以 status 输出为准。
4. 只在有新增免费模型、模型下线或被改价时，用简体中文给用户发一条简短消息列出变化；无变化则保持沉默。
不要修改 pi 的任何配置文件，sync 只允许 --dry-run。

> 接入方式二选一：
> - Muse 环境：用 Muse 的 cron 工具直接导入本文件（frontmatter 即任务定义，路径中的 `$HOME` 会在运行时展开）。
> - 裸机环境：系统 cron / launchd / systemd timer。例（crontab -e）：
>   `0 8 * * * /usr/bin/python3 $HOME/workspace/skills/freetoken-bots/scripts/radar.py scan`
>   注意：系统级 cron 只负责触发扫描，步骤 1/3/4 的"快照 + diff + 通知"需要自行包进一个 shell 脚本。
