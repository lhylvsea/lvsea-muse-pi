---
name: pi-agent-workflow
description: 在新机器上复刻 pi 编程助手工作流（安装、ling 免费 provider 配置、OpenRouter 免费模型池、每日定时巡检）的操作手册。
---

# pi-agent-workflow

记录本机 pi 编程助手（`@earendil-works/pi-coding-agent`）的完整工作流——安装、配置、用法、免费模型池、定时任务。目标：其他智能体读了本 skill 就能照着搭出来、用起来。

> 安全红线：任何文件都不得出现 API key 原值。密钥位置一律用环境变量占位符 `$LING_API_KEY`、`$OPENROUTER_API_KEY` 表示；`models.json` 的 `apiKey` 字段用 `!bash -ic 'echo $LING_API_KEY'` 在运行时读取，文件内不落盘。

## 1. 安装

```bash
# 全局安装（本机 npm prefix = ~/.npm-global，二进制落在 ~/.npm-global/bin/pi）
npm install -g @earendil-works/pi-coding-agent
```

验证：`pi --version`（本机为 1.2.0）。

**VM 重置后的恢复注意点：**
- VM 重置会清空全局 npm 包：重跑上面的 `npm install -g` 即可恢复 `pi` 命令。
- 密钥 export 在 `~/.bashrc`（`LING_API_KEY` / `OPENROUTER_API_KEY`）：重置后需重新写入并 `source ~/.bashrc`（或开新终端）。
- `~/.pi/agent/settings.json` 与 `models.json` 若丢失，用本 skill `config/` 下的脱敏模板恢复，或直接跑 `scripts/install.sh` 一键重建。
- PATH 必须包含 npm 全局 bin 目录（本机为 `~/.npm-global/bin`）。

一键安装：`bash scripts/install.sh`（只装环境、不写任何密钥）。

## 2. 配置

配置文件：`~/.pi/agent/settings.json` + `~/.pi/agent/models.json`（脱敏模板见 `config/settings.json.example`、`config/models.json.example`）。

**settings.json 关键字段：**
- `defaultProvider`: `ling`
- `defaultModel`: `Ling-3.1-flash`
- `defaultThinkingLevel`: `high`
- `enabledModels`: `["ling/Ling-3.1-flash"]`
- `packages`: 5 个扩展包（见下表）
- `extensions`: `["-builtin:mcp"]`（禁用内置 MCP，由 pi-mcp-adapter 接管）

**models.json 关键字段（ling provider）：**
- `baseUrl`: `https://api.ant-ling.com/v1`
- `api`: `openai-completions`
- `apiKey`: `!bash -ic 'echo $LING_API_KEY'`（pi 运行时执行该命令从环境变量取值，文件内无密钥）
- `authHeader`: `true`；`compat.supportsDeveloperRole`: `false`
- 模型 `Ling-3.1-flash`：`reasoning: true`；`thinkingLevelMap` 覆盖 minimal/low/medium/high/xhigh；`contextWindow: 256000`；`maxTokens: 32000`；`cost` 全 0（免费）

**5 个扩展包（settings.json 的 `packages` 字段）与作用：**

| 包 | 作用 |
|---|---|
| `npm:pi-mcp-adapter` | MCP 适配器扩展，接管并替换 pi 内置 MCP 支持（因此 `extensions` 里要 `-builtin:mcp`） |
| `npm:pi-web-access` | Web 搜索、URL 抓取、GitHub 仓库克隆、PDF 抽取、YouTube 与本地视频分析 |
| `npm:@tintinweb/pi-subagents` | Claude Code 风格的子代理与工作流编排（并行执行、舰队视图、运行中途 steering） |
| `npm:@ff-labs/pi-fff` | FFF 驱动的模糊文件与内容搜索（ffgrep / fffind 工具） |
| `npm:pi-context-prune` | 裁剪未来上下文，同时保留原始工具调用历史 |

扩展包由 pi 首次启动时按 `packages` 字段自动安装到 `~/.pi/agent/npm/`。

## 3. 用法

- **一次性任务**：`pi -p "任务描述" </dev/null`
  **必须带 `</dev/null`**：非交互环境下 pi 会尝试读 stdin，不重定向会挂起。所有无人值守的 `pi -p` 调用一律遵守这条。
- **多轮交互**：直接运行 `pi` 进入交互式会话。
- **验证模型注册**：`pi --list-models`，本机应输出 `ling / Ling-3.1-flash / 256K / 32K / thinking=yes`。
- **pong 冒烟测试**：`pi -p 'say pong' --no-extensions </dev/null`——不加载扩展，最快验证 provider 与 key 通路。

## 4. 免费模型池（freetoken-bots 流程）

配套雷达：`~/workspace/skills/freetoken-bots`（`scripts/radar.py`）。OpenRouter 免费资格是**动态**的，池子靠每日扫描维护（见第 5 节）。

流程四步：
1. **scan**：`python3 scripts/radar.py scan` 拉 OpenRouter catalog，免费名单写入 `~/.pi/agent/freetoken-bots.json`。字段结构：`checked_at`（扫描时间）、`eligible`（已验证免费且参数 ≥100B 的旗舰池）、`needs_parameter_verification`（`[{id, context_length}]`，免费但参数量未独立核实）、`free_ids`（全部免费 ID 数组）、`free_count`。
2. **参数量 ≥100B 独立验证**：只有从可信模型/厂商文档**独立核实**总参数 ≥100B 的才能进 `eligible`；`/models` API 缺参数字段时留在 `needs_parameter_verification`，**绝不**从模型名猜 100B。
3. **probe tool 调用**：子代理候选必须 `supported_parameters` 含 `tools`，并用一次**真实工具调用**独立探测；普通 completion 探测不能证明支持 tools。命令：`OPENROUTER_API_KEY=... python3 scripts/radar.py probe --model 'exact/openrouter-id:free'`。
4. **sync 只做 proposal**：`python3 scripts/radar.py sync --dry-run` 只输出对 `models.json` 的候选 diff，**不自动改配置**；应用前须显式批准、备份原文件、原子写入、校验（`python3 -m json.tool`、`pi --list-models`、pong 测试），失败回滚。绝不覆盖 ling provider 与 `enabledModels`。

完整红线见 `docs/free-models.md`。

## 5. 定时任务

免费资格每天变，定时扫描**必须配**（内容模板见 `crons/`，接入方式见 `docs/scheduling.md`）：

| 任务 | 时间（本地时区） | 目的 |
|---|---|---|
| `freetoken-bots-daily-scan` | 每天 08:00 | radar.py 全量扫描：先快照上次 free_ids（scan 会覆盖报告文件），再扫描、diff 出新增/下线/改价模型，有变化才发简体中文消息，无变化沉默 |
| `openrouter-free-watch` | 每天 09:46 | 独立第二信号：check.py 拉 OpenRouter 公开 models API（无需鉴权）与 baseline.json 做 diff，名单变化才通知；拉取失败等 2 分钟重试一次，仍失败记 `last_error.txt` 后沉默 |

两条共同纪律：无变化保持沉默；不改 pi 任何配置文件（sync 只允许 `--dry-run`）。

接入二选一：Muse 的 cron 工具（直接吃 `crons/*.md` 的 frontmatter 格式），或系统 cron / launchd / systemd timer（裸机平台）。
