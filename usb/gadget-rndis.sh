#!/bin/sh
# RNDIS 变体：仅用于「只支持 Win7/老 Win10」的单独固件 SKU。
# 铁律：不要和 NCM 同时暴露（双配置会导致 Windows 偶发选错驱动）。
set -e
GADGET=/sys/kernel/config/usb_gadget/cb
mkdir -p "$GADGET"; cd "$GADGET"
echo 0x1d6b > idVendor; echo 0x0105 > idProduct; echo 0x0200 > bcdUSB
mkdir -p configs/c.1; mkdir -p functions/rndis.usb0
echo 250 > configs/c.1/MaxPower
ln -sf functions/rndis.usb0 configs/c.1/
ls /sys/class/udc > UDC
sleep 0.3
ip link set usb0 up
ip addr add 192.168.7.1/24 dev usb0
