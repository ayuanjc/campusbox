#!/bin/sh
# 上行状态机：有线优先，无墙口回落校园 WiFi。
# 每 10s 判一次；切换时不做「先断后连」，而是新增默认路由再删旧的（避免切换真空）。
# 判据不看「接口 up」，只看「能不能通」——墙口常有 link 但没有 DHCP/没有 Portal。

STATE=/run/cb/uplink.state
LOG=/data/logs/cb.log
. /lib/functions.sh

log() { echo "$(date '+%F %T') uplink: $*" >> $LOG; }
cur=unknown
echo "none" > $STATE

probe() {
  # 1) 有地址吗 2) 能到网关吗 3) 能出校园网吗（Portal 墙内的 204 也算通）
  iface=$1; gw=$2
  ip -4 addr show dev "$iface" 2>/dev/null | grep -q "inet " || return 1
  ping -c1 -W2 -I "$iface" "$gw" >/dev/null 2>&1 || return 1
  return 0
}

switch_to() {
  to=$1
  case "$to" in
    eth0)
      gw=$(uci -q get network.wan.gateway); [ -n "$gw" ] || gw=$(ip route | awk '/default/ {print $3; exit}')
      ip route replace default via "$gw" dev eth0 metric 10
      ;;
    wlan0)
      gw=$(ip route show dev wlan0 | awk '/default/ {print $3; exit}')
      [ -n "$gw" ] || gw=192.168.1.1
      ip route replace default via "$gw" dev wlan0 metric 20
      ;;
  esac
  log "switch $cur -> $to"
  echo "$to" > $STATE
  cur=$to
}

wifi_up() {
  SSID=$(uci -q get campusbox.uplink.ssid)
  PSK=$(uci -q get campusbox.uplink.psk)
  [ -n "$SSID" ] || return 1
  if ! wpa_cli -i wlan0 status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
    log "connecting wifi ssid=$SSID"
    wpa_cli -i wlan0 add_network >/dev/null 2>&1 || true
    id=$(wpa_cli -i wlan0 add_network | tail -1)
    wpa_cli -i wlan0 set_network "$id" ssid "\"$SSID\"" >/dev/null 2>&1
    wpa_cli -i wlan0 set_network "$id" psk "\"$PSK\"" >/dev/null 2>&1
    wpa_cli -i wlan0 select_network "$id" >/dev/null 2>&1
    sleep 8
  fi
  wpa_cli -i wlan0 status 2>/dev/null | grep -q "wpa_state=COMPLETED" || return 1
  # 等 DHCP
  i=0
  while [ $i -lt 6 ]; do
    ip -4 addr show dev wlan0 | grep -q "inet " && return 0
    udhcpc -i wlan0 -q -n -t 2 >/dev/null 2>&1
    i=$((i+1)); sleep 3
  done
  return 1
}

while true; do
  # --- 优先级 1：有线 ---
  if probe eth0 0.0.0.0 2>/dev/null || ip -4 addr show dev eth0 2>/dev/null | grep -q "inet "; then
    [ "$cur" = eth0 ] || switch_to eth0
  else
    # --- 优先级 2：校园 WiFi ---
    if wifi_up; then
      [ "$cur" = wlan0 ] || switch_to wlan0
    else
      [ "$cur" = none ] || { log "no uplink"; echo "none" > $STATE; cur=none; }
    fi
  fi
  sleep 10
done
