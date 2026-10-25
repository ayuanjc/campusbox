#!/bin/sh
# VBUS 电压监测 + 三档软降档（v0.2 核心机制，零成本）
#
# 为什么必须有：AP 模式满功率 3.3V 峰值 830mA → 5V 侧 644mA，超 USB2.0 标称 500mA 29%。
# 主机不会告诉你它撑不撑得住，只会「掉压 → 复位」或者「直接过流保护」。
# 唯一可观测的信号是 VBUS 电压：主机限流时 5V 会被拉低。
#
# 硬件前提：VBUS 经 1/3 分压（10k/20k）进 ADC0，量程 5V → 1.67V。
#           分压比由硬件保证，软件只读 raw 再换算。

ADC=$(uci -q get campusbox.power.adc_path); [ -n "$ADC" ] || ADC=/sys/bus/iio/devices/iio:device0/in_voltage0_raw
REF_MV=$(uci -q get campusbox.power.adc_ref_mv); [ -n "$REF_MV" ] || REF_MV=1800
FULL=$(uci -q get campusbox.power.adc_full); [ -n "$FULL" ] || FULL=4095
DIV=3
STATE=/run/cb/vbus.state
LOG=/data/logs/cb.log

log() { echo "$(date '+%F %T') vbus: $*" >> $LOG; }

vbus_mv() {
  raw=$(cat "$ADC" 2>/dev/null) || { echo 0; return; }
  echo $(( raw * REF_MV / FULL * DIV ))
}

set_profile() {
  p=$1
  [ "$(cat $STATE 2>/dev/null)" = "$p" ] && return 0
  case "$p" in
    full)
      echo 800000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null
      iwpriv wlan0 set_txpower 18 2>/dev/null || iw dev wlan0 set txpower fixed 1800 2>/dev/null
      ;;
    mid)
      echo 700000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null
      iwpriv wlan0 set_txpower 15 2>/dev/null || iw dev wlan0 set txpower fixed 1500 2>/dev/null
      ;;
    low)
      echo 600000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null
      iwpriv wlan0 set_txpower 12 2>/dev/null || iw dev wlan0 set txpower fixed 1200 2>/dev/null
      ;;
    safe)
      killall hostapd 2>/dev/null
      echo 600000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null
      iwpriv wlan0 set_txpower 12 2>/dev/null
      ;;
  esac
  echo "$p" > $STATE
  log "profile -> $p (vbus=$(cat /run/cb/vbus.mv 2>/dev/null)mV)"
}

lowcnt=0
while true; do
  mv=$(vbus_mv)
  echo $mv > /run/cb/vbus.mv
  if [ "$mv" -ge 4750 ]; then
    lowcnt=0; set_profile full
  elif [ "$mv" -ge 4600 ]; then
    lowcnt=0; set_profile mid
  elif [ "$mv" -ge 4400 ]; then
    lowcnt=0; set_profile low
  else
    lowcnt=$((lowcnt+1))
    log "vbus low $mv mV x$lowcnt"
    [ $lowcnt -ge 3 ] && set_profile safe
  fi
  sleep 1
done
