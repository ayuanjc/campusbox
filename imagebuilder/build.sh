#!/bin/sh
# 用 imagebuilder 产出固件。需先设置 IB_DIR 指向解包后的 imagebuilder 目录。
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/build}
IB=${IB_DIR:?请设置 IB_DIR=/path/to/openwrt-imagebuilder-*}
mkdir -p "$OUT"

# 先装配 overlay（含 /etc/cb 下所有设备端脚本）
sh "$ROOT/tests/stage.sh"

cp "$ROOT/imagebuilder/config.seed" "$IB/.config"
make -C "$IB" image PROFILE=${PROFILE:-} PACKAGES="$(tr '\n' ' ' < "$ROOT/imagebuilder/packages.txt")" \
     FILES="$ROOT/build/stage" 2>&1 | tail -20

cp "$IB"/bin/targets/*/*/*.img.gz "$OUT"/ 2>/dev/null || true
ls -lh "$OUT"/ 2>/dev/null || true
