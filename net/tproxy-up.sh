#!/bin/sh
# 策略路由 + 分流规则（v0.2：双客户端接口 + 双上行）
# 关键：table 100 里必须有 local default —— 少了它，tproxy 会把包送回路由表形成环路，
#       症状是「一连就超时，CPU 却很低」。这是 TPROXY 最常见的坑。
set -e
ip rule add fwmark 1 lookup 100 2>/dev/null || true
ip route add local default dev lo table 100 2>/dev/null || true

# AP 网段与客户端网段互通（否则手机连上 AP 但打不开 192.168.7.1 面板）
ip route add 192.168.8.0/24 dev wlan1 2>/dev/null || true

nft -f /etc/cb/nftables-cb.nft
echo 1 > /proc/sys/net/ipv4/ip_forward
