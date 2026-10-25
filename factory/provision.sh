#!/bin/sh
# 产线烧号：SN / MAC / iSerial。CSV 格式: serial,mac_usb0,mac_wlan
set -e
CSV=${1:?用法: provision.sh units.csv}
[ -f "$CSV" ] || exit 1

while IFS=, read -r sn mac_usb mac_wl; do
  [ -z "$sn" ] && continue
  case "$sn" in \#*) continue;; esac
  uci set campusbox.usb.serial="$sn"
  echo "$mac_usb" > /factory/mac_usb0
  echo "$mac_wl"  > /factory/mac_wlan
  uci commit campusbox
  echo "provisioned $sn"
done < "$CSV"
