#!/bin/sh
# 把所有设备端脚本装配成一份可直接覆盖到设备根的 overlay。
# 输出：build/stage/  ——  内容 = rootfs-overlay/ + /etc/cb/*  + /usr/sbin/panel-state
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/stage"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -r "$ROOT/rootfs-overlay/." "$OUT/"

mkdir -p "$OUT/etc/cb"
cp "$ROOT/usb/"*.sh            "$OUT/etc/cb/" 2>/dev/null || true
cp "$ROOT/net/"*               "$OUT/etc/cb/" 2>/dev/null || true
cp "$ROOT/mihomo/"*            "$OUT/etc/cb/" 2>/dev/null || true
cp "$ROOT/portal/"*.sh         "$OUT/etc/cb/" 2>/dev/null || true
cp "$ROOT/uplink/"*.sh         "$OUT/etc/cb/" 2>/dev/null || true
cp "$ROOT/wifi/"*              "$OUT/etc/cb/" 2>/dev/null || true

# 面板状态脚本放进 PATH，产线治具直接调用
mkdir -p "$OUT/usr/sbin"
cp "$ROOT/panel/state.sh" "$OUT/usr/sbin/panel-state"

chmod +x "$OUT"/etc/cb/*.sh "$OUT"/usr/sbin/* 2>/dev/null || true
echo "staged -> $OUT"
find "$OUT" -type f | wc -l
