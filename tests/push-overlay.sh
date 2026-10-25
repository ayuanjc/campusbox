#!/bin/sh
# 把 overlay 推到已连接设备（研发期用）
G=${1:-192.168.7.1}
[ -d rootfs-overlay ] || exit 1
tar -C rootfs-overlay -cf - . | ssh root@$G "tar -xf - -C / && /etc/init.d/campusbox restart"
