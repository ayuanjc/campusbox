#!/bin/sh
# 用 imagebuilder 产出固件。需先设置 IB_DIR 指向解包后的 imagebuilder 目录。
set -e
OUT=${1:-./build}
IB=${IB_DIR:?请设置 IB_DIR=/path/to/openwrt-imagebuilder-*}
mkdir -p "$OUT"

cp config.seed "$IB/.config"
make -C "$IB" image PROFILE=${PROFILE:-} PACKAGES="$(tr '\n' ' ' < packages.txt)" \
     FILES="$(cd "$(dirname "$0")/.." && pwd)/rootfs-overlay" 2>&1 | tail -20

cp "$IB"/bin/targets/*/*/*.img.gz "$OUT"/ 2>/dev/null || true
ls -lh "$OUT"
