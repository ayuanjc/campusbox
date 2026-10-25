#!/bin/sh
# Dr.COM 三步认证：取状态 → 认证 → (掉线时)登出。
# 参数全部从 uci /etc/config/campusbox 读，不硬编码。
set -e
. /lib/functions.sh

cfg() { uci -q get campusbox.portal.$1; }

USERID=$(cfg username)
PASSWD=$(cfg password)
PORTAL=$(cfg portal_host)
WLAN=$(cfg wlan_if)

[ -z "$USERID" ] && { echo "未配置账号"; exit 2; }
[ -z "$PORTAL" ] && PORTAL=172.32.253.17

# 关键：强制不走代理（等价于 py 里的 ProxyHandler({})）
export http_proxy= https_proxy= all_proxy=
CURL="curl -s --noproxy '*' --max-time 8"

# 拿当前 MAC / IP / 接入参数（从 302 重定向里抓，抓不到就用本机值）
MAC=$(cat /sys/class/net/$WLAN/address)
IP=$(ip -4 addr show $WLAN | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)

# step1: 取 id/timestamp/uuid
S1=$($CURL "http://$PORTAL/PortalJsonAction.do?viewStatus=1" || true)
ID=$(echo "$S1" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
TS=$(echo "$S1" | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p')
UUID=$(echo "$S1" | sed -n 's/.*"uuid":"\([^"]*\)".*/\1/p')

# step2: 认证明文（authByRas=false）
$CURL -G "http://$PORTAL/quickauth.do" \
  --data-urlencode "userid=$USERID" \
  --data-urlencode "passwd=$PASSWD" \
  --data-urlencode "wlanuserip=$IP" \
  --data-urlencode "mac=$MAC" \
  --data-urlencode "id=$ID" --data-urlencode "timestamp=$TS" --data-urlencode "uuid=$UUID" \
  || exit 1

echo "auth done for $USERID @ $IP"
