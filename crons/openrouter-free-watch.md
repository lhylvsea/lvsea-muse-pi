---
id: openrouter-free-watch
title: 白嫖与监控Openrouter免费模型
enabled: true
owner: goal:openrouter-free-model-watch
mode: task
schedule:
  kind: daily
  timezone: '@user.current'
  time: 09:46:00
delivery:
  - chat_id: <Muse 投递目标 chat_id>
metadata:
  tags: [cron:flexible-time]
  presentation_locale: zh-CN
---
# OpenRouter 免费模型每日巡检

## 任务
1. 运行 `python3 $HOME/workspace/openrouter-watch/check.py`。它拉取 OpenRouter 公开 models API（无需鉴权），与 `baseline.json` 做 diff，自动更新基线，并输出 JSON 结果。
2. 根据输出决定是否打扰用户：
   - `added` 或 `removed` 非空 → 用简体中文给用户发一条简短消息：列出新增/下线的免费模型 ID；只陈述名单变化，不做无法验证的价值点评。
   - 无变化（两项都为空）→ 保持沉默，不要发消息。
   - `ok: false`（拉取失败）→ 等 2 分钟重试一次；仍失败则沉默，把错误记入 `$HOME/workspace/openrouter-watch/last_error.txt`，不要打扰用户。
3. 除更新基线和错误日志外，不要写其他文件，不要建报告文档。

## 边界
- 只监控免费模型名单（`:free` 及定价为 0 的模型）。OpenRouter 的免费额度赠送/促销活动没有公开 API，本任务覆盖不到；用户若问起额度活动，另行处理。
- 消息语气匹配用户：简短直接，只说变化。

> 接入方式二选一：
> - Muse 环境：用 Muse 的 cron 工具直接导入本文件（frontmatter 即任务定义，路径中的 `$HOME` 会在运行时展开）。
> - 裸机环境：系统 cron / launchd / systemd timer。例（crontab -e）：
>   `46 9 * * * /usr/bin/python3 $HOME/workspace/openrouter-watch/check.py`
>   注意：系统级 cron 只负责触发 check.py，"通知用户"的逻辑需要自行包进调用脚本。
