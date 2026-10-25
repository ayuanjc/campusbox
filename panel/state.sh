#!/bin/sh
# 把内部状态汇总成一行 JSON，供面板与产线治具读（治具不靠肉眼看 LED）。
LINK=$(cat /run/cb/link 2>/dev/null || echo unknown)
BAL=$(cat /run/cb/state.json 2>/dev/null || echo '{}')
UP=$(ip -4 addr show usb0 >/dev/null 2>&1 && echo 1 || echo 0)
MIH=$(pgrep -f 'mihomo -d' >/dev/null && echo 1 || echo 0)
SN=$(uci -q get campusbox.usb.serial)
printf '{"link":"%s","usb0":%s,"mihomo":%s,"serial":"%s","balance":%s}\n' \
  "$LINK" "$UP" "$MIH" "$SN" "$BAL"
