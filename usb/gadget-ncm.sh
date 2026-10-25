#!/bin/sh
# 把板子配置成 USB 网卡（CDC-NCM）。这是整个项目的地基。
# 依赖: kmod-usb-gadget-ncm, libcomposite
set -e

GADGET=/sys/kernel/config/usb_gadget/cb
DEV_MAC=${DEV_MAC:-02:aa:bb:cc:dd:01}
HOST_MAC=${HOST_MAC:-02:aa:bb:cc:dd:02}

[ -d "$GADGET" ] && umount_gadget() { :; }

mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

mkdir -p "$GADGET"
cd "$GADGET"

echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0200 > bcdUSB
echo 0x0100 > bcdDevice

mkdir -p strings/0x409
echo "CampusBox" > strings/0x409/manufacturer
echo "CampusBox NCM" > strings/0x409/product
# iSerial = CB<hwrev>-<feature><sn>  见 docs/INTERFACE-CONTRACT.md
echo "${CB_SERIAL:-CB01-F0-00000000}" > strings/0x409/serialnumber

mkdir -p configs/c.1/strings/0x409
echo "NCM" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower     # 250 x 2mA = 500mA

mkdir -p functions/ncm.usb0
echo "$DEV_MAC"  > functions/ncm.usb0/dev_addr
echo "$HOST_MAC" > functions/ncm.usb0/host_addr
ln -sf functions/ncm.usb0 configs/c.1/

ls /sys/class/udc > UDC            # 上线：主机这一刻枚举
sleep 0.3
ip link set usb0 up
ip addr add 192.168.7.1/24 dev usb0
echo "gadget up: usb0 = 192.168.7.1/24"
