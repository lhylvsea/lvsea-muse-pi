# 定时任务设计

## 为什么必须每天 08:00 扫描

- OpenRouter 的免费资格是**动态**的：模型会随时被下架或恢复收费，事先没有任何通知。
- 免费名单是消耗品：`probe` 的 fail-closed 解析把超过 24 小时的扫描视为过期并先刷新；名单过期会把请求路由到已失效或已收费的变体。
- 雷达自己不会动：freetoken-bots 技能**不主动扫描**，必须由外部定时任务每天触发。
- 因此每天早上 8 点（本地时区）跑一次，保证当天的工作从一份新鲜名单开始。
- 安装时必须明确告诉用户："这个 skill 需要每天早上 8 点跑一次扫描定时任务，不配的话免费名单会过期，它自己不会动。" 不要把它呈现为无需定时器即可工作。

## 两个任务的分工

| | freetoken-bots-daily-scan | openrouter-free-watch |
|---|---|---|
| 时间 | 每天 08:00（`@user.current` 本地时区） | 每天 09:46（`@user.current` 本地时区，flexible-time） |
| 入口 | `$HOME/workspace/skills/freetoken-bots/scripts/radar.py scan` | `$HOME/workspace/openrouter-watch/check.py` |
| 数据源 | OpenRouter catalog（含定价细节，需 scan 落盘） | OpenRouter 公开 models API，**无需鉴权** |
| 产出 | 覆盖写 `~/.pi/agent/freetoken-bots.json`；快照上次 free_ids 到 `$HOME/workspace/goals/openrouter-free-model-watch/hidden_files/freetoken-free-ids-<日期>.json` 保证可完整对比 | 与 `baseline.json` 做 diff 并自动更新基线；输出 JSON 结果 |
| 通知 | 有新增/下线/改价才发简体中文消息；无变化沉默 | `added`/`removed` 非空才发简短消息；无变化沉默 |
| 失败处理 | scan 失败即任务失败 | `ok: false` 等 2 分钟重试一次；仍失败记 `$HOME/workspace/openrouter-watch/last_error.txt` 后沉默 |
| 边界 | 不改 pi 任何配置文件，sync 只允许 `--dry-run` | 只监控免费名单（`:free` 及定价 0）；免费额度赠送/促销无公开 API，覆盖不到 |

两者互补：scan 盯"当前池子还能不能免费用"（深度），watch 盯"整个名单有没有变"（广度、独立第二信号、不需要 key）。

## 接入方式（按平台二选一）

1. **Muse 环境**：用 Muse 的 cron 工具，直接导入 `crons/*.md`——frontmatter 里的 `schedule`（`kind: daily` / `time` / `timezone: '@user.current'`）即任务定义，正文即任务步骤。
2. **裸机环境**：系统 cron / launchd / systemd timer，三者选一个并保持。例（crontab -e）：
   ```
   0 8 * * * /usr/bin/python3 $HOME/workspace/skills/freetoken-bots/scripts/radar.py scan
   ```
   注意：系统级定时只负责触发命令，cron 模板正文里的"快照 + diff + 有变化才通知"逻辑需要自行包进一个 shell 脚本。
3. 每次扫描后与上一份报告对比：浮出新上线、下架、被改价的模型以及 `eligible` 池的变化。
