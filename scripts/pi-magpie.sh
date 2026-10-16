#!/bin/bash
# pi-magpie — 用 Magpie 免费网关备用池跑 pi（主力 ling 不动）。
# 网关没跑会自动拉起。默认模型 kilo-auto/free（自动路由），可用 --model 指定或 MAGPIE_MODEL 环境变量覆盖。
# 用法：pi-magpie -p "帮我看看这个报错" [--model magpie/zen-free-all/longcat-2.5-preview-free]
set -u
export PATH="$HOME/.npm-global/bin:$PATH"
GW="http://127.0.0.1:3425"
KEY_FILE="$HOME/.config/magpie/web-key"
LOG_DIR="$HOME/workspace/logs"; LOG="$LOG_DIR/magpie-gateway.log"

if ! curl -sf --max-time 5 "$GW/v1/models" >/dev/null 2>&1; then
  mkdir -p "$LOG_DIR"
  if [ ! -f "$KEY_FILE" ]; then openssl rand -hex 16 > "$KEY_FILE"; chmod 600 "$KEY_FILE"; fi
  MAGPIE_WEB_KEY="$(cat "$KEY_FILE")" nohup magpie web --gateway --no-open --addr 127.0.0.1:18700 >>"$LOG" 2>&1 &
  for _ in $(seq 1 30); do
    sleep 2
    curl -sf --max-time 3 "$GW/v1/models" >/dev/null 2>&1 && break
  done
  curl -sf --max-time 5 "$GW/v1/models" >/dev/null 2>&1 || { echo "pi-magpie: 网关启动失败，看 $LOG" >&2; exit 1; }
fi

MODEL="${MAGPIE_MODEL:-magpie/kilo-free-all/kilo-auto/free}"
has_model=0
for a in "$@"; do [ "$a" = "--model" ] && has_model=1 && break; done
if [ "$has_model" = 0 ]; then
  exec pi --provider magpie --model "$MODEL" "$@"
else
  exec pi --provider magpie "$@"
fi
