#!/bin/sh
# mihomo 不解析 subscription-userinfo 响应头，所以自己读。
# 每 3 分钟跑一次，写 /run/cb/state.json 供面板与治具读。
set -e
OUT=/run/cb/state.json
SUBS=/etc/cb/subs.txt
[ -f "$SUBS" ] || exit 0

tot_up=0; tot_down=0; tot_all=0; lines=""
while IFS= read -r url; do
  [ -z "$url" ] && continue
  case "$url" in \#*) continue;; esac
  hdr=$(curl -sI --max-time 8 "$url" | tr -d '\r')
  ui=$(echo "$hdr" | grep -i '^subscription-userinfo:' | cut -d' ' -f2-)
  [ -z "$ui" ] && continue
  up=$(echo "$ui" | sed -n 's/.*upload=\([0-9]*\).*/\1/p')
  dn=$(echo "$ui" | sed -n 's/.*download=\([0-9]*\).*/\1/p')
  ta=$(echo "$ui" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
  [ -z "$ta" ] && continue
  tot_up=$((tot_up + ${up:-0})); tot_down=$((tot_down + ${dn:-0})); tot_all=$((tot_all + ta))
done < "$SUBS"

left=$((tot_all - tot_up - tot_down))
[ $left -lt 0 ] && left=0
mkdir -p /run/cb
cat > "$OUT" <<EOF
{"total":$tot_all,"used":$((tot_up + tot_down)),"left":$left,"ts":$(date +%s)}
EOF
