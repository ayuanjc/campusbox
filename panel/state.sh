#!/bin/sh
# 把内部状态汇总成一行 JSON，供面板与产线治具读（治具不靠肉眼看 LED）。
# v0.2 新增：uplink（当前上行）、vbus（mV）、power（降档档位）、ap（AP 客户端数）
LINK=$(cat /run/cb/link 2>/dev/null || echo unknown)
BAL=$(cat /run/cb/state.json 2>/dev/null || echo '{}')
UP=$(ip -4 addr show usb0 >/dev/null 2>&1 && echo 1 || echo 0)
MIH=$(pgrep -f 'mihomo -d' >/dev/null && echo 1 || echo 0)
SN=$(uci -q get campusbox.usb.serial)
UPLINK=$(cat /run/cb/uplink.state 2>/dev/null || echo none)
VBUS=$(cat /run/cb/vbus.mv 2>/dev/null || echo 0)
POWER=$(cat /run/cb/vbus.state 2>/dev/null || echo unknown)
APN=$(iw dev wlan1 station dump 2>/dev/null | grep -c Station || echo 0)
printf '{"link":"%s","usb0":%s,"mihomo":%s,"serial":"%s","uplink":"%s","vbus_mv":%s,"power":"%s","ap_clients":%s,"balance":%s}\n' \
  "$LINK" "$UP" "$MIH" "$SN" "$UPLINK" "$VBUS" "$POWER" "$APN" "$BAL"
