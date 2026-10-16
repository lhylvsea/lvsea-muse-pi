# Magpie 免费网关（pi 备用免费模型池）

## 这是什么

[Magpie](https://usemagpie.ai)（yetone / nxtreaming）：跑在本机的多协议 AI 网关，能把各家模型的接口翻译成统一的 OpenAI / Anthropic / Gemini 协议。本机只用它的**终端版**（`magpie-cli`，无 GUI 依赖）。

社区插件 `github:lesnolie/magpie-free-gateways` 提供两个互不冲突的免费供应商：

| 供应商 | 上游 | 模型数（2026-10-16） | 登录方式 |
|---|---|---|---|
| `zen-free-all` | OpenCode Zen 免费目录 | 13（含 `longcat-2.5-preview-free`、`mimo-v2.6-flash-free` 等） | 公开凭据，填 `public` |
| `kilo-free-all` | Kilo Gateway 零价目录 | 18（含 `kilo-auto/free`、`openrouter/free` 两个自动路由） | 选"匿名免费访问"，填 `anonymous` |

模型列表由插件**每小时从上游实时目录刷新**，新增/下线无需更新插件。链路：

```
pi → 本地网关 127.0.0.1:3425/v1（OpenAI 兼容）→ Zen / Kilo 免费模型
```

**定位：纯备用。**主力 `ling` 不动，默认 provider 永远是 `ling`。

## 安装（一键）

```bash
bash scripts/install-magpie.sh
```

脚本做完这 5 步（全部无个人密钥，可重跑）：装 `magpie-cli` → 装插件 → 匿名登录两家 → 生成网关 web-key → 给 pi 加备用 provider。手动等价步骤：

```bash
# 1. 先看一眼官方安装脚本（SHA-256 自校验），再执行
curl -fsSL https://usemagpie.ai/install.sh -o /tmp/magpie-install.sh
MAGPIE_BIN_DIR=$HOME/.npm-global/bin MAGPIE_CLI=1 sh /tmp/magpie-install.sh

# 2. 装插件（仓库未发 npm，从 GitHub 装）
magpie plugin add github:lesnolie/magpie-free-gateways

# 3. 登录：zen 的 key 从 stdin 读；kilo 先选方法序号 1 再填 anonymous
echo "public" | magpie plugin login zen-free-all
printf '1\nanonymous\n' | magpie plugin login kilo-free-all

# 4. 验证：两家 signedIn: true 且有模型
magpie plugin --json
```

## 启动网关

```bash
[ -f ~/.config/magpie/web-key ] || { openssl rand -hex 16 > ~/.config/magpie/web-key; chmod 600 ~/.config/magpie/web-key; }
MAGPIE_WEB_KEY="$(cat ~/.config/magpie/web-key)" magpie web --gateway --no-open --addr 127.0.0.1:18700
```

- 网关 API **固定**在 `127.0.0.1:3425`：`/v1/models`、`/v1/chat/completions`；本机回环免鉴权。
- 模型 ID 形如 `zen-free-all/longcat-2.5-preview-free`（网关命名空间前缀 + 上游模型 ID）。
- `/v1/models` 会隐藏 `jev-1.13-free`（它是 System One 分类器，不进聊天列表），属正常现象。

冒烟测试（网关起好后）：

```bash
curl -s -X POST http://127.0.0.1:3425/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"zen-free-all/longcat-2.5-preview-free","messages":[{"role":"user","content":"say OK"}],"max_tokens":20}' 
```

## pi 备用 provider 配置

`~/.pi/agent/models.json` 加一个 `magpie` provider（其余原样，**不动 ling**）：

```json
"magpie": {
  "baseUrl": "http://127.0.0.1:3425/v1",
  "api": "openai-completions",
  "apiKey": "!bash -ic 'cat ~/.config/magpie/web-key'",
  "authHeader": true,
  "compat": { "supportsDeveloperRole": false },
  "models": [
    { "id": "zen-free-all/longcat-2.5-preview-free", "name": "Zen: LongCat 2.5 Preview (free)",
      "reasoning": true, "input": ["text"], "contextWindow": 1000000, "maxTokens": 131072,
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 } },
    { "id": "kilo-free-all/kilo-auto/free", "name": "Kilo: Auto Free Router",
      "reasoning": true, "input": ["text"], "contextWindow": 256000, "maxTokens": 32768,
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 } }
  ]
}
```

`settings.json` 的 `enabledModels` 追加 `"magpie/zen-free-all/longcat-2.5-preview-free"` 等引用；`defaultProvider` 保持 `ling`。

本机实际配了 8 个模型（另有 `mimo-v2.6-flash-free`、`deepseek-v4.1-flash-free`、`big-pickle`、`space-bunny-free`、`openrouter/free`、`cohere/north-mini-code:free`），以 `magpie plugin --json` 的实时列表为准增减。

## 切换方法

```bash
# 最省事：包装脚本（网关没跑自动拉起，默认 kilo-auto/free）
bash scripts/pi-magpie.sh -p "任务描述" </dev/null

# 手动指定模型
pi --provider magpie --model "magpie/zen-free-all/longcat-2.5-preview-free" -p "任务描述" </dev/null

# 查可用模型 / 回主力
pi --list-models magpie
pi -p "任务描述" </dev/null          # 默认走 ling，不变
```

`</dev/null` 是硬要求：非交互环境下 `pi -p` 会尝试读 stdin，不重定向就挂起。

## 每日巡检

模板：`crons/magpie-plugin-watch.md`（每天约 08:46，`@user.current` 时区）。执行脚本 `scripts/magpie-plugin-watch.sh`：

1. `git ls-remote https://github.com/lesnolie/magpie-free-gateways HEAD` 取最新 commit，与 `~/.config/magpie/free-gateways.hash` 比对；
2. 无变化 → 静默退出（退出码 0）；
3. 有变化 → `magpie plugin update` → 重启网关 → 验证（`magpie plugin --json` 两家 signedIn 且有模型、`curl /v1/models` 可列）→ 更新 hash（退出码 1 = 成功需通知，2 = 失败需通知）。

纪律：无变化绝不打扰；绝不改动 ling 配置。

## 坑与红线

- `pi -p` 非交互**必须**带 `</dev/null`（血泪教训：没带会静默挂起十几分钟，日志全空）。
- `magpie plugin login` 的 key 从 stdin 读；kilo 登录是两步（先输 `1` 选匿名，再输 `anonymous`）。
- VM 重置会丢 npm 全局包（`magpie` 二进制）：重跑 `scripts/install-magpie.sh` 即可；`~/.config/magpie`（登录态、插件、web-key）在 home 分区，保留。
- `pkill -f "magpie web"` 会把**自己的 shell 也匹配杀掉**（命令行里带了模式串）：用 `pkill -f "[m]agpie web"` 避开自匹配。
- 隐私红线：请求走 Kilo / OpenCode 公开网关，**别传敏感代码和 key**；Kilo 匿名按 IP 每小时 200 次——备用池场景够用。
- 不动主力：`defaultProvider`/`defaultModel` 永远 `ling`/`Ling-3.1-flash`；改 `models.json` 前先备份。
- `mimo-v2.6-flash-free` 在 public 凭据下偶发限流（上游对共享凭据的配额），换 `longcat-2.5-preview-free` 或 `kilo-auto/free` 即可。
