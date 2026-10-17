# AnyRouter 免费档（pi 第三免费 fallback）

## 这是什么

[AnyRouter](https://anyrouter.dev)（anyrouter.dev）：OpenAI 兼容的多供应商网关，200+ 模型，key 前缀 `sk-ar-v1-`，接口 `https://anyrouter.dev/api/v1`，模型 ID 形如 `provider/model`。

免费套餐自带 `anyrouter/free` 与一批 `:free` 模型：**无日限、注册不要绑卡、真 $0**。这部分直接给 pi 当免费 fallback 用。

**定位：第三棒。**回退链 `kilo → zen → anyrouter`（见 `scripts/pi-reason.sh`），主力 `ling` 不动。

**不碰的部分：** 每天签到送的 `$25` 是付费模型额度，Fable 5.1 这类模型一次任务能花掉 `$9.88`——都不适合拿来跑定时任务。链路里**只接免费档**，定时任务永远烧不到余额。自动签到刷额度不搞。

## 接入（三步）

```bash
# 1. 去 anyrouter.dev 注册（不要绑卡），在后台 API Keys 里建一个 key（sk-ar-v1- 开头）
# 2. key 走安全通道交给操作员（不要贴聊天、不要进文件），存进 Secure Vault 的 custom.anyrouter
# 3. 起本地代理（key 不落地：每请求现场向 Vault 取 surrogate，出口处换成真 key）
nohup python3 scripts/anyrouter-proxy.py >>~/workspace/logs/anyrouter-proxy.log 2>&1 &
```

代理监听 `127.0.0.1:3426`，把 `/v1/*` 转发到 `https://anyrouter.dev/api/v1/*`。冒烟测试：

```bash
curl -s -m 20 http://127.0.0.1:3426/v1/models | head -c 300
# 应返回 OpenAI 风格 {"object":"list","data":[...]}，即 key/位置/主机三者都对
```

## pi provider 配置

`~/.pi/agent/models.json` 加一个 `anyrouter` provider（其余原样，**不动 ling**）：

```json
"anyrouter": {
  "api": "openai-completions",
  "apiKey": "anyrouter-local-proxy",
  "authHeader": true,
  "baseUrl": "http://127.0.0.1:3426/v1",
  "compat": { "supportsDeveloperRole": false },
  "models": [
    { "id": "anyrouter/free", "name": "AnyRouter Free Router (free tier, no credits)",
      "reasoning": true, "input": ["text"], "contextWindow": 200000, "maxTokens": 32000,
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 } }
  ]
}
```

`apiKey` 填占位即可：真鉴权在代理层完成，pi 发来的头会被代理替换掉。

直接调用：

```bash
pi --provider anyrouter --model anyrouter/free -p "任务描述" </dev/null
```

## 回退链（scripts/pi-reason.sh）

cron 推理统一入口，链路：

```
0. 查网关：magpie 127.0.0.1:3425 不通则拉起；anyrouter 代理 127.0.0.1:3426 不通则拉起（挂了不致命）
1. pi --provider magpie --model kilo-free-all/kilo-auto/free
2. 失败 → pi --provider magpie --model zen-free-all/longcat-2.5-preview-free
3. 失败 → pi --provider anyrouter --model anyrouter/free
4. 都失败 → 打印 PI_UNAVAILABLE，exit 3，调用方降级本地执行并记 ~/workspace/logs/pi-fallback.log
```

```bash
pi-reason.sh "<prompt>" [tag]            # prompt 直接给
pi-reason.sh @/path/to/prompt.txt [tag]  # 长提示词从文件读
PI_REASON_TIMEOUT=90 pi-reason.sh ...    # 单次 pi 超时秒数，默认 150
```

## 坑与红线

- 代理只转交 `/v1/*` 路径，其他路径 502。
- 每个转发请求现场取一次 surrogate：Vault 连接被删/吊销时代理报 `DynamicCredentialError`，先查连接状态再重连。
- 免费档路由每次可能落到不同模型：它是兜底，不是定点模型，别拿它做质量敏感的活。
- 隐私红线：免费档是共享池，**别传敏感代码和 key**（和 magpie 免费池同一条规矩）。
- 不动主力：`defaultProvider`/`defaultModel` 永远 `ling`/`Ling-3.1-flash`；改 `models.json` 前先备份。
- VM 重置会丢代理进程（脚本在 `scripts/` 里，home 分区保留）：`pi-reason.sh` 每次运行自动拉起，无需手动。
