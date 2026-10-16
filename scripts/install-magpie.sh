#!/usr/bin/env bash
# ============================================================================
# Magpie 免费网关一键安装（pi 备用免费模型池）
# 做 5 件事：装 magpie-cli → 装 free-gateways 插件 → 匿名登录两家 →
#           生成网关 web-key → 给 pi 加 magpie 备用 provider（主力 ling 不动）。
# 安全红线：只用公开凭据（zen: public / kilo: anonymous），不写任何个人 key。
# 可重跑：已装过的步骤会自动跳过；改 pi 配置前先备份。
# ============================================================================
set -euo pipefail

echo "==> [1/5] 安装 magpie-cli（终端版）"
BIN_DIR="${MAGPIE_BIN_DIR:-$HOME/.npm-global/bin}"
if ! command -v magpie >/dev/null 2>&1; then
  curl -fsSL https://usemagpie.ai/install.sh -o /tmp/magpie-install.sh
  echo "    官方安装脚本已下载到 /tmp/magpie-install.sh（自带 SHA-256 校验），开始执行…"
  MAGPIE_BIN_DIR="$BIN_DIR" MAGPIE_CLI=1 sh /tmp/magpie-install.sh
else
  echo "    magpie 已安装：$(magpie --version)，跳过"
fi
export PATH="$BIN_DIR:$PATH"

echo "==> [2/5] 安装插件 github:lesnolie/magpie-free-gateways"
magpie plugin add github:lesnolie/magpie-free-gateways

echo "==> [3/5] 登录（公开凭据，无个人 key）"
echo "public" | magpie plugin login zen-free-all
printf '1\nanonymous\n' | magpie plugin login kilo-free-all

echo "==> [4/5] 生成网关 web-key（~/.config/magpie/web-key，600 权限）"
KEY_FILE="$HOME/.config/magpie/web-key"
if [ ! -f "$KEY_FILE" ]; then
  openssl rand -hex 16 > "$KEY_FILE"; chmod 600 "$KEY_FILE"
  echo "    已生成"
else
  echo "    已存在，跳过"
fi
# 巡检用 hash 文件初始化（仓库当前 HEAD）
if [ ! -f "$HOME/.config/magpie/free-gateways.hash" ]; then
  git ls-remote https://github.com/lesnolie/magpie-free-gateways HEAD 2>/dev/null | awk '{print $1}' > "$HOME/.config/magpie/free-gateways.hash" || true
fi

echo "==> [5/5] 给 pi 加 magpie 备用 provider（备份原配置，主力 ling 不动）"
python3 <<'PYEOF'
import json, shutil, datetime, os
base = os.path.expanduser("~/.pi/agent")
ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
os.makedirs(base, exist_ok=True)

meta = [
    ("zen-free-all/longcat-2.5-preview-free", "Zen: LongCat 2.5 Preview (free)", 1000000, 131072),
    ("zen-free-all/mimo-v2.6-flash-free", "Zen: MiMo V2.6 Flash (free)", 200000, 32000),
    ("zen-free-all/deepseek-v4.1-flash-free", "Zen: DeepSeek V4.1 Flash (free)", 200000, 32000),
    ("zen-free-all/big-pickle", "Zen: Big Pickle (free)", 200000, 32000),
    ("zen-free-all/space-bunny-free", "Zen: Space Bunny (free)", 1048576, 524288),
    ("kilo-free-all/kilo-auto/free", "Kilo: Auto Free Router", 256000, 32768),
    ("kilo-free-all/openrouter/free", "Kilo: OpenRouter Free Router", 200000, 4096),
    ("kilo-free-all/cohere/north-mini-code:free", "Kilo: Cohere North Mini Code (free)", 256000, 64000),
]
models = [{
    "id": mid, "name": name, "reasoning": True, "input": ["text"],
    "contextWindow": ctx, "maxTokens": mt,
    "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
} for mid, name, ctx, mt in meta]

mj_path = f"{base}/models.json"
if os.path.exists(mj_path):
    shutil.copy(mj_path, f"{mj_path}.bak-{ts}")
    mj = json.load(open(mj_path))
else:
    mj = {"providers": {}}
mj.setdefault("providers", {})["magpie"] = {
    "baseUrl": "http://127.0.0.1:3425/v1",
    "api": "openai-completions",
    "apiKey": "!bash -ic 'cat ~/.config/magpie/web-key'",
    "authHeader": True,
    "compat": {"supportsDeveloperRole": False},
    "models": models,
}
json.dump(mj, open(mj_path, "w"), ensure_ascii=False, indent=2)
print("    models.json 已写入 magpie provider（原文件已备份）")

sj_path = f"{base}/settings.json"
if os.path.exists(sj_path):
    shutil.copy(sj_path, f"{sj_path}.bak-{ts}")
    sj = json.load(open(sj_path))
else:
    sj = {"defaultProvider": "ling", "defaultModel": "Ling-3.1-flash", "enabledModels": []}
sj.setdefault("enabledModels", [])
for mid, _, _, _ in meta:
    ref = f"magpie/{mid}"
    if ref not in sj["enabledModels"]:
        sj["enabledModels"].append(ref)
# 主力不动：没有 defaultProvider 才写 ling
sj.setdefault("defaultProvider", "ling")
json.dump(sj, open(sj_path, "w"), ensure_ascii=False, indent=2)
print("    settings.json 已追加 enabledModels，defaultProvider =", sj["defaultProvider"])
PYEOF

echo ""
echo "验证："
echo "  magpie plugin --json            # 两家 signedIn: true 且有模型"
echo "  pi --list-models magpie         # 应列出 8 个 magpie/ 模型"
echo ""
echo "启动网关："
echo "  MAGPIE_WEB_KEY=\"\$(cat ~/.config/magpie/web-key)\" magpie web --gateway --no-open --addr 127.0.0.1:18700"
echo ""
echo "日常使用（网关没跑自动拉起）："
echo "  bash $(dirname "$0")/pi-magpie.sh -p \"任务描述\" </dev/null"
echo ""
echo "别忘了配每日巡检（模板见 crons/magpie-plugin-watch.md）。"
