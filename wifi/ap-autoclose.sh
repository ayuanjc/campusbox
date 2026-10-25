#!/bin/sh
# AP 默认 10 分钟无客户端自动关：热与电的双重要求（规格书 §9.4 / §8.4）。
IDLE_LIMIT=$(uci -q get campusbox.ap.idle_minutes); [ -n "$IDLE_LIMIT" ] || IDLE_LIMIT=10
IF=wlan1
LOG=/data/logs/cb.log
idle=0

log() { echo "$(date '+%F %T') ap: $*" >> $LOG; }

while true; do
  sleep 60
  n=$(iw dev $IF station dump 2>/dev/null | grep -c Station)
  if [ "$(cat /run/cb/vbus.state 2>/dev/null)" = "safe" ]; then
    idle=0; continue
  fi
  if [ "$n" -eq 0 ]; then
    idle=$((idle+1))
    if [ $idle -ge $IDLE_LIMIT ]; then
      log "no client for $idle min -> stop hostapd"
      killall hostapd 2>/dev/null
      idle=0
    fi
  else
    idle=0
  fi
done
