#!/bin/bash
# 每日巡检：lesnolie/magpie-free-gateways 仓库有无新 commit
# 退出码：0=无变化（静默）；1=有更新并同步验证成功（需通知用户）；2=失败（需通知用户）
set -u
export PATH="$HOME/.npm-global/bin:$PATH"
REPO="https://github.com/lesnolie/magpie-free-gateways"
HASH_FILE="$HOME/.config/magpie/free-gateways.hash"
KEY_FILE="$HOME/.config/magpie/web-key"
LOG_DIR="$HOME/workspace/logs"; LOG="$LOG_DIR/magpie-plugin-watch.log"
GW="http://127.0.0.1:3425"
mkdir -p "$LOG_DIR"

remote=$(git ls-remote "$REPO" HEAD 2>/dev/null | awk '{print $1}')
if [ -z "$remote" ]; then
  echo "$(date '+%F %T') 获取远程 commit 失败" >>"$LOG"; exit 2
fi
local_hash="$(cat "$HASH_FILE" 2>/dev/null || echo none)"
if [ "$remote" = "$local_hash" ]; then exit 0; fi

echo "$(date '+%F %T') 发现新 commit: ${local_hash:0:8} -> ${remote:0:8}，开始同步" >>"$LOG"
if ! magpie plugin update >>"$LOG" 2>&1; then
  echo "$(date '+%F %T') magpie plugin update 失败" >>"$LOG"; exit 2
fi

# 重启网关以加载新插件代码
pkill -f "[m]agpie web --gateway" 2>/dev/null
sleep 3
if [ ! -f "$KEY_FILE" ]; then echo "$(date '+%F %T') 缺少 web-key" >>"$LOG"; exit 2; fi
MAGPIE_WEB_KEY="$(cat "$KEY_FILE")" nohup magpie web --gateway --no-open --addr 127.0.0.1:18700 >>"$LOG_DIR/magpie-gateway.log" 2>&1 &
for _ in $(seq 1 30); do
  sleep 2
  curl -sf --max-time 3 "$GW/v1/models" >/dev/null 2>&1 && break
done

# 验证：两 provider 已登录且有模型 + 网关能列出模型
if ! magpie plugin --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
need={'kilo-free-all','zen-free-all'}
seen={p['id'] for p in d.get('providers',[]) if p.get('signedIn') and len(p.get('models',[]))>0}
sys.exit(0 if need<=seen else 1)"; then
  echo "$(date '+%F %T') 更新后验证失败：provider 登录/模型列表异常" >>"$LOG"; exit 2
fi
if ! curl -sf --max-time 20 "$GW/v1/models" 2>/dev/null | grep -q "kilo-free-all/kilo-auto/free"; then
  echo "$(date '+%F %T') 网关模型列表验证失败" >>"$LOG"; exit 2
fi
echo "$remote" > "$HASH_FILE"
echo "$(date '+%F %T') 同步成功，已更新到 ${remote:0:8}" >>"$LOG"
exit 1
