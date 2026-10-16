# 免费模型池：完整流程与红线

提炼自 freetoken-bots 雷达技能（`~/workspace/skills/freetoken-bots/SKILL.md`）。pi 是执行层；Muse / Grokbot / Dot 等宿主只能在能执行 shell 命令或访问独立部署的 Pi 服务时调用它，本池子不替代任何产品的原生模型。

## "免费"的定义

- 免费 = OpenRouter catalog 里 `pricing.prompt == 0` 且 `pricing.completion == 0`，且任何显式 request/cache 价格也为 0。
- 免费资格是**动态**的，不是永久承诺——模型会随时下架或恢复收费。

## 红线（违反任何一条都可能产生付费调用或错误路由）

1. **fail-closed 模型解析（v0.1.1）**：`probe --model` 绝不信任手敲的 ID，一律对最新一次扫描结果解析——
   - 精确命中已验证免费 ID → 直接使用；
   - 缺 `:free` 后缀 → 自动补齐并**大声警告**（静默丢弃后缀会路由到**付费**变体，这个错误已经在真实调用里发生过一次）；
   - 其他任何 ID → 直接拒绝，绝不猜测。
   - 扫描过期（>24h）先刷新再解析。
2. **永不自动路由到付费模型**：402、额度耗尽、限流都不是删除用户现有 pi provider 配置的理由。
3. **probe 必须验证 tools 支持**：子代理候选要求 `supported_parameters` 含 `tools`，且用一次**真实工具调用**独立探测；普通 completion 探测不能证明 tools 支持。
4. **≥100B 参数量独立验证**：只有从可信模型/厂商文档核实总参数 ≥100B 才能进 `eligible` 旗舰池；`/models` API 缺参数字段时留在 `needs_parameter_verification`；**绝不**从模型名猜 100B。
5. **密钥不入库、不打印**：不要把 API key 写进 Git 或打印出来；live probing 需要 `OPENROUTER_API_KEY` 而未设置时，提示用户输入。
6. **不重写 pi 设置**：改 `models.json` 前必须保留用户已有 providers/defaults，并校验已装 pi 的 schema。
7. **无人值守必须 `</dev/null`**：所有 `pi -p` 调用重定向 stdin。
8. **sync 只做 proposal**：`radar.py sync` 目前只输出候选 diff，故意不修改 `models.json`（Pi schema 与模型标识符必须先在已装 pi 上验证过才能做写入集成）。这是安全的 MVP，不是自动路由器。

## 完整流程（scan → 验证 → probe → sync）

1. **scan**：`python3 scripts/radar.py scan` → 写入 `~/.pi/agent/freetoken-bots.json`（私有报告）。
2. **参数核实**：从可信模型/厂商文档解析参数量；只有独立核实 ≥100B 的进 `eligible` 池。
3. **probe**：先普通 completion，再单独一次真实 `tools` 调用；区分 429（临时限流）与硬性日额度耗尽。
4. **候选 diff**：核对 OpenRouter 模型 ID、provider 兼容性、context/maxTokens 字段；生成候选 diff，**不覆盖** ling 自定义 provider 与 `enabledModels`。
5. **应用（需显式批准）**：备份原文件 → 原子写入 → `python3 -m json.tool` 校验 → `pi --list-models` → `pi -p 'say pong' --no-extensions </dev/null`；任一步失败则回滚。
6. **宿主集成（Muse/Grokbot/Dot）**：使用受控的 shell 子代理调用；先确认宿主能执行本地 pi 命令、能访问共享工作区、能捕获结果；绝不在无认证情况下把 pi 的 shell/API 暴露到公网。
7. **任务前确认**：大任务前问用户用哪个模型；自动 fallback 需用户明确开启（opt-in）；完成状态不确定时绝不重放有副作用的动作。

## 池子选择策略

- 优先"已验证免费 ≥100B 且支持 tools"的模型；
- 若操作上更合适，单独报告更小的支持 tools 的免费模型；
- 没有候选通过时**报空池**，绝不静默 fallback 到付费 token。

## 每次运行后的对比纪律

- 与上一份报告比较：浮出新上线的免费模型、下架的模型、被改价（不再免费）的模型、`eligible` 池的任何变化。
- ChatGPT 式提醒/监控不会改本机；重复的瞬时错误确认后再标记模型不可用；`eligible`、`needs_parameter_verification`、非活跃三种状态分开存放。
