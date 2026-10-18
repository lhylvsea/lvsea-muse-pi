# Radox AI 免费档（pi 第四免费 fallback）

## 这是什么

[Radox AI](https://radoxai.com)：第三方 OpenAI 兼容中转站，33 个模型，接口 `https://radoxai.com/v1`，`Authorization: Bearer <key>` 鉴权。

免费套餐：每月 **10M tokens**，不用绑卡，每月重置。这部分给 pi 当免费 fallback 用。

**定位：第四棒。**回退链 `kilo → zen → anyrouter → radox`（见 `scripts/pi-reason.sh`），主力 `ling` 不动。

**先说丑话：** 模型名全是中转站自己标的（`claude-opus-5.5`、`claude-fable-5.1`……），实际跑的是什么、质量如何都没验证过；有用户实测后称 fake；免费随时可能结束（博主原话）。把它当多一层兜底，别当主力。

## 接入（四步）

```bash
# 1. 去 radoxai.com 注册，在后台 API Keys 里建一个 key
# 2. key 走安全通道交给操作员（不要贴聊天、不要进文件），存进 Secure Vault 的 custom.radox
# 3. 起本地代理（key 不落地：每请求现场向 Vault 取 surrogate，出口处换成真 key）
nohup python3 scripts/radox-proxy.py >>~/workspace/logs/radox-proxy.log 2>&1 &
```

代理监听 `127.0.0.1:3427`，把 `/v1/*` 转发到 `https://radoxai.com/v1/*`。冒烟测试：

```bash
curl -s -m 25 http://127.0.0.1:3427/v1/models | head -c 300
# 应返回 OpenAI 风格 {"object":"list","data":[...]}，即 key/位置/主机三者都对
```

## pi provider 配置

`~/.pi/agent/models.json` 加一个 `radox` provider（其余原样，**不动 ling**）：

```json
"radox": {
  "api": "openai-completions",
  "apiKey": "radox-local-proxy",
  "authHeader": true,
  "baseUrl": "http://127.0.0.1:3427/v1",
  "compat": { "supportsDeveloperRole": false },
  "models": [
    { "id": "claude-opus-5.5", "name": "Radox: Claude Opus 5.5 (free tier 10M/mo, relay label)",
      "reasoning": true, "input": ["text"], "contextWindow": 200000, "maxTokens": 32000,
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 } }
  ]
}
```

`apiKey` 填占位即可：真鉴权在代理层完成，pi 发来的头会被代理替换掉。

直接调用：

```bash
pi --provider radox --model claude-opus-5.5 -p "任务描述" </dev/null
```

## 回退链（scripts/pi-reason.sh）

cron 推理统一入口，链路：

```
0. 查网关：magpie 127.0.0.1:3425 / anyrouter 代理 127.0.0.1:3426 / radox 代理 127.0.0.1:3427，
   不通则尝试拉起（radox 挂了不致命，跳过本棒）
1. pi --provider magpie --model kilo-free-all/kilo-auto/free
2. 失败 → pi --provider magpie --model zen-free-all/longcat-2.5-preview-free
3. 失败 → pi --provider anyrouter --model anyrouter/free
4. 失败 → pi --provider radox --model claude-opus-5.5
5. 都失败 → 打印 PI_UNAVAILABLE，exit 3，调用方降级本地执行并记 ~/workspace/logs/pi-fallback.log
```

## 坑与红线

- radoxai.com 前面有 Cloudflare：**不带浏览器头的请求会被 1010 拦掉**（裸 curl / python-urllib 都不行），代理转发时固定带浏览器 `User-Agent` 和 `Accept: application/json`。排障先查这个。
- 代理只转交 `/v1/*` 路径，其他路径 502。
- 每个转发请求现场取一次 surrogate：Vault 连接被删/吊销时代理报 `DynamicCredentialError`，先查连接状态再重连。
- 每月 10M 额度用完会 429/402：等下月重置，或让链路自然降级。
- 隐私红线：第三方中转，**别传敏感代码和 key**（和 magpie/anyrouter 免费池同一条规矩）。
- 不动主力：`defaultProvider`/`defaultModel` 永远 `ling`/`Ling-3.1-flash`；改 `models.json` 前先备份。
- VM 重置会丢代理进程（脚本在 `scripts/` 里，home 分区保留）：`pi-reason.sh` 每次运行自动拉起，无需手动。
