#!/bin/sh
# 策略路由：被打标的包送本地 tproxy
set -e
ip rule add fwmark 1 lookup 100 2>/dev/null || true
ip route add local default dev lo table 100 2>/dev/null || true
nft -f /etc/cb/nftables-usb0.nft
echo 1 > /proc/sys/net/ipv4/ip_forward
