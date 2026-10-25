#!/bin/sh
# 20 秒探 generate_204；失败则指数退避到 120 秒并重新认证。
set -e
CB=/etc/cb
INTERVAL=20
MAX=120

probe() { curl -s --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 5 \
  "http://connectivitycheck.gstatic.com/generate_204" 2>/dev/null; }

while :; do
  code=$(probe)
  if [ "$code" = "204" ]; then
    echo "online" > /run/cb/link
    INTERVAL=20
  else
    echo "offline($code)" > /run/cb/link
    sh $CB/campus-auth.sh || true
    INTERVAL=$((INTERVAL * 2)); [ $INTERVAL -gt $MAX ] && INTERVAL=$MAX
  fi
  sleep $INTERVAL
done
