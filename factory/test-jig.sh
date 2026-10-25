#!/bin/sh
# 一拖多治具：对每台设备跑 6 项判定。读设备侧 JSON，不靠肉眼。
# 依赖: 设备插在 hub 上，逐台登录 192.168.7.1 检查。
set -u
HOST=${HOST:-192.168.7.1}
fail=0

chk() { printf '%-28s' "$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS"; else echo "FAIL"; fail=$((fail+1)); fi; }

chk "T1 面板可达"        curl -sf --max-time 5 "http://$HOST/"
chk "T2 状态接口"        curl -sf --max-time 5 "http://$HOST/api/state"
chk "T3 mihomo 在跑"     sh -c "curl -sf http://$HOST/api/state | grep -q '\"mihomo\":1'"
chk "T4 usb0 已起"       sh -c "curl -sf http://$HOST/api/state | grep -q '\"usb0\":1'"
chk "T5 SN 已烧"         sh -c "curl -sf http://$HOST/api/state | grep -qv '\"serial\":\"\"'"
chk "T6 DHCP 正常"       sh -c "ip route get $HOST >/dev/null"

echo "----"
[ $fail -eq 0 ] && echo "全部通过" || echo "失败 $fail 项"
exit $fail
