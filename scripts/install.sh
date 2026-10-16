#!/usr/bin/env bash
# ============================================================================
# pi-agent-workflow 一键安装脚本
# 作用：安装 pi 编程助手、创建 ~/.pi/agent 目录骨架、写入无密钥配置模板。
# 安全红线：本脚本不含任何 API key / 密钥；密钥只通过环境变量
#           $LING_API_KEY 和 $OPENROUTER_API_KEY 在运行时注入。
# ============================================================================
set -euo pipefail

echo "==> [1/4] 全局安装 pi 编程助手 (@earendil-works/pi-coding-agent)"
npm install -g @earendil-works/pi-coding-agent

echo "==> [2/4] 创建 ~/.pi/agent 目录骨架"
AGENT_DIR="$HOME/.pi/agent"
mkdir -p "$AGENT_DIR/extensions"

echo "==> [3/4] 写入配置模板 settings.json / models.json（纯模板，不含密钥）"
# 已存在的配置先备份，绝不覆盖用户已有设置
for f in settings.json models.json; do
  if [ -f "$AGENT_DIR/$f" ]; then
    cp "$AGENT_DIR/$f" "$AGENT_DIR/$f.bak.$(date +%Y%m%d%H%M%S)"
    echo "    已备份原 $f"
  fi
done

cat > "$AGENT_DIR/settings.json" <<'EOF'
{
  "defaultProvider": "ling",
  "defaultModel": "Ling-3.1-flash",
  "defaultThinkingLevel": "high",
  "enabledModels": [
    "ling/Ling-3.1-flash"
  ],
  "packages": [
    "npm:pi-mcp-adapter",
    "npm:pi-web-access",
    "npm:@tintinweb/pi-subagents",
    "npm:@ff-labs/pi-fff",
    "npm:pi-context-prune"
  ],
  "extensions": [
    "-builtin:mcp"
  ]
}
EOF

cat > "$AGENT_DIR/models.json" <<'EOF'
{
  "providers": {
    "ling": {
      "baseUrl": "https://api.ant-ling.com/v1",
      "api": "openai-completions",
      "apiKey": "!bash -ic 'echo $LING_API_KEY'",
      "authHeader": true,
      "compat": {
        "supportsDeveloperRole": false
      },
      "models": [
        {
          "id": "Ling-3.1-flash",
          "name": "Ant Ling 3.1 Flash",
          "reasoning": true,
          "thinkingLevelMap": {
            "minimal": "minimal",
            "low": "low",
            "medium": "medium",
            "high": "high",
            "xhigh": "xhigh"
          },
          "input": ["text"],
          "contextWindow": 256000,
          "maxTokens": 32000,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
EOF

echo "    已写入。可对照本 skill 的 config/*.example 检查。"

echo "==> [4/4] PATH 检查"
NPM_GLOBAL_BIN="$(npm prefix -g)/bin"
if ! echo ":$PATH:" | grep -q ":$NPM_GLOBAL_BIN:"; then
  echo "    注意：$NPM_GLOBAL_BIN 不在 PATH 中。"
  echo "    请在 ~/.bashrc 末尾加入：export PATH=\"$NPM_GLOBAL_BIN:\$PATH\"，然后 source ~/.bashrc"
else
  echo "    OK：$NPM_GLOBAL_BIN 已在 PATH 中"
fi

echo ""
echo "最后一步（必须手动做，脚本不写任何密钥）——export 两个环境变量："
echo "  export LING_API_KEY=<你的 ling API key>"
echo "  export OPENROUTER_API_KEY=<你的 OpenRouter API key>"
echo "建议写入 ~/.bashrc 后执行 source ~/.bashrc。"
echo ""
echo "验证："
echo "  pi --version"
echo "  pi --list-models                      # 应列出 ling / Ling-3.1-flash"
echo "  pi -p 'say pong' --no-extensions </dev/null"
echo ""
echo "别忘了配置每日定时任务（见 crons/ 与 docs/scheduling.md）："
echo "每天 08:00 的免费模型扫描必须配，不配的话免费名单会过期失效。"
