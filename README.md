# pi-agent-workflow

pi 编程助手（`@earendil-works/pi-coding-agent`）在本机的完整工作流档案：安装、免费模型配置、定时巡检。供其他智能体（人或 AI）照着复刻到新机器上。

## 总览

- 默认 provider：`ling`（`baseUrl: https://api.ant-ling.com/v1`，openai-completions 协议）
- 默认模型：`Ling-3.1-flash`（thinking level `high`，256K 上下文 / 32K max output，成本全 0）
- 5 个扩展：`pi-mcp-adapter` / `pi-web-access` / `@tintinweb/pi-subagents` / `@ff-labs/pi-fff` / `pi-context-prune`
- 免费模型池：freetoken-bots 雷达（scan → ≥100B 独立验证 → probe tool 调用 → sync 只做 proposal）
- 定时任务：每天 08:00 免费模型扫描 + 09:46 OpenRouter 名单巡检

## 安装步骤

1. 全局安装 pi：`npm install -g @earendil-works/pi-coding-agent`（或一键 `bash scripts/install.sh`）
2. export 两个环境变量（写入 `~/.bashrc` 后 `source`）：
   ```bash
   export LING_API_KEY=<你的 ling API key>
   export OPENROUTER_API_KEY=<你的 OpenRouter API key>
   ```
3. 验证：`pi --list-models` 应列出 `ling / Ling-3.1-flash`；冒烟测试 `pi -p 'say pong' --no-extensions </dev/null`
4. 配置每日定时任务（见下节）——不配的话免费名单会过期

## 密钥占位符说明

- 本仓库**任何文件都不含密钥原值**。
- `$LING_API_KEY`：ling provider 的 API key。`models.json` 里以 `!bash -ic 'echo $LING_API_KEY'` 形式声明，pi 运行时从环境变量读取，密钥不落盘。
- `$OPENROUTER_API_KEY`：OpenRouter 鉴权，radar.py 的 `probe` 需要（`scan` / `status` 拉公开 catalog，不需要 key）。
- 从旧机器迁移时，密钥藏在 `~/.bashrc` 与 `~/.pi/agent/auth.json` 里——复制配置只复制**结构与字段名**，绝不复制值。

## 定时任务接入说明

两个每日任务（模板在 `crons/`，设计理由在 `docs/scheduling.md`）：

1. `freetoken-bots-daily-scan`（08:00）：radar.py 全量扫描 + 快照对比 + 有变化才通知
2. `openrouter-free-watch`（09:46）：公开 API 名单 diff 的独立第二信号

接入按平台二选一：
- **Muse 环境**：用 Muse 的 cron 工具，直接导入 `crons/*.md`（frontmatter 已带 schedule 字段）
- **裸机**：系统 cron / launchd / systemd timer，例：`0 8 * * * /usr/bin/python3 $HOME/workspace/skills/freetoken-bots/scripts/radar.py scan`（注意系统级接入需自行把"快照 + diff + 通知"包进 shell 脚本）

## 目录结构

```
lvsea-muse-pi/
├── SKILL.md                        # 机器可读 skill 正文（安装/配置/用法/免费模型池/定时任务）
├── README.md                       # 本文件：人类总览
├── scripts/install.sh              # 一键安装脚本（不含密钥，只提示 export）
├── config/
│   ├── settings.json.example       # settings.json 脱敏模板
│   └── models.json.example         # models.json 脱敏模板（apiKey 为运行时读取命令，非密钥）
├── crons/
│   ├── freetoken-bots-daily-scan.md  # 每日 08:00 扫描任务模板
│   └── openrouter-free-watch.md      # 每日 09:46 名单巡检任务模板
└── docs/
    ├── free-models.md              # 免费模型池完整流程与红线
    └── scheduling.md               # 定时任务设计：为什么必须每天 8 点、分工、接入方式
```
