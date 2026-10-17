#!/usr/bin/env bash
# pi-reason.sh — cron 推理统一入口：把 Muse agent 的推理工作转给 pi 免费模型，省 tokens。
#
# 回退链：
#   0. 每个 cron 开头统一先检查网关：curl -s -m 5 http://127.0.0.1:3425/v1/models；
#      不通则尝试拉起（最多等约 60 秒）。AnyRouter 本地代理（127.0.0.1:3426）同理检查拉起。
#   1. pi --provider magpie --model kilo-free-all/kilo-auto/free -p "<prompt>" </dev/null
#   2. 失败/空回退 zen：pi --provider magpie --model zen-free-all/longcat-2.5-preview-free ...
#   3. 再失败回退 AnyRouter 免费档：pi --provider anyrouter --model anyrouter/free ...
#      （走本地代理 127.0.0.1:3426，真 $0 免费 tier，不烧签到送的 $25 额度）
#   4. 都失败 → stdout 打印 "PI_UNAVAILABLE: <原因>"，exit 3；
#      调用方（cron worker）改为自己推理，并在本次运行记录里如实注明
#      "pi 免费模型不可用，已降级为本地执行"。
#
# 用法：
#   pi-reason.sh "<prompt>" [tag]             # prompt 直接给
#   pi-reason.sh @/path/to/prompt.txt [tag]  # prompt 从文件读（长提示词用这个）
#   PI_REASON_TIMEOUT=90 pi-reason.sh ...     # 单次 pi 调用的超时秒数，默认 150
#
# 成功：exit 0，stdout = pi 回答正文
# tag 用于降级日志 ~/workspace/logs/pi-fallback.log 的标记（建议传 cron id）
set -uo pipefail
export PATH="$HOME/.npm-global/bin:$PATH"
PI=/home/hatch/.npm-global/bin/pi
GW="http://127.0.0.1:3425"
AR_GW="http://127.0.0.1:3426"
AR_PROXY="$HOME/workspace/custom-connectors/custom.anyrouter/bin/anyrouter-proxy.py"
KILO_MODEL="kilo-free-all/kilo-auto/free"
ZEN_MODEL="zen-free-all/longcat-2.5-preview-free"
AR_MODEL="anyrouter/free"
TIMEOUT="${PI_REASON_TIMEOUT:-150}"
FALLBACK_LOG="$HOME/workspace/logs/pi-fallback.log"

PROMPT="${1:?pi-reason.sh: need prompt}"
TAG="${2:-cron}"
if [[ "$PROMPT" == @* ]]; then PROMPT="$(cat "${PROMPT#@}")"; fi

log_fallback() {  # $1 = reason
  mkdir -p "$(dirname "$FALLBACK_LOG")"
  printf '%s [%s] PI_UNAVAILABLE: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$TAG" "$1" >>"$FALLBACK_LOG"
}

# --- 0. 网关检查（不通则尝试拉起） ---
if ! curl -sf --max-time 5 "$GW/v1/models" >/dev/null 2>&1; then
  KEY_FILE="$HOME/.config/magpie/web-key"
  if [ ! -f "$KEY_FILE" ]; then openssl rand -hex 16 > "$KEY_FILE"; chmod 600 "$KEY_FILE"; fi
  MAGPIE_WEB_KEY="$(cat "$KEY_FILE")" nohup magpie web --gateway --no-open --addr 127.0.0.1:18700 \
    >>"$HOME/workspace/logs/magpie-gateway.log" 2>&1 &
  for _ in $(seq 1 20); do
    sleep 3
    curl -sf --max-time 3 "$GW/v1/models" >/dev/null 2>&1 && break
  done
fi
if ! curl -sf --max-time 5 "$GW/v1/models" >/dev/null 2>&1; then
  R="magpie 网关 127.0.0.1:3425 不可达且拉起失败"
  log_fallback "$R"; echo "PI_UNAVAILABLE: $R"; exit 3
fi
# --- 0b. AnyRouter 本地代理检查（不通则尝试拉起；挂了不致命，只记日志） ---
if ! curl -sf --max-time 5 "$AR_GW/v1/models" >/dev/null 2>&1; then
  if [ -f "$AR_PROXY" ]; then
    nohup python3 "$AR_PROXY" >>"$HOME/workspace/logs/anyrouter-proxy.log" 2>&1 &
    for _ in $(seq 1 10); do
      sleep 2
      curl -sf --max-time 3 "$AR_GW/v1/models" >/dev/null 2>&1 && break
    done
  fi
fi
AR_OK=0
curl -sf --max-time 5 "$AR_GW/v1/models" >/dev/null 2>&1 && AR_OK=1

run_pi() {  # $1 = provider, $2 = model id
  timeout "$TIMEOUT" "$PI" --provider "$1" --model "$2" -p "$PROMPT" </dev/null 2>"/tmp/pi-reason-${TAG}.err"
}

OUT="$(run_pi magpie "$KILO_MODEL")"; RC=$?
if [ $RC -eq 0 ] && [ -n "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; then
  printf '%s\n' "$OUT"; exit 0
fi
OUT="$(run_pi magpie "$ZEN_MODEL")"; RC=$?
if [ $RC -eq 0 ] && [ -n "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; then
  printf '%s\n' "$OUT"; exit 0
fi
if [ "$AR_OK" = 1 ]; then
  OUT="$(run_pi anyrouter "$AR_MODEL")"; RC=$?
  if [ $RC -eq 0 ] && [ -n "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$OUT"; exit 0
  fi
fi
R="kilo($KILO_MODEL)、zen($ZEN_MODEL)、anyrouter($AR_MODEL) 免费模型均调用失败，stderr 见 /tmp/pi-reason-${TAG}.err"
log_fallback "$R"; echo "PI_UNAVAILABLE: $R"; exit 3
