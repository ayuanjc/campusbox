# CampusBox

插到电脑上就多一块网卡：设备自己连校园网（**有线优先，无墙口则 WiFi**）、自己过 Dr.COM Portal 认证、按规则分流；还能自己开一个 WiFi 热点给手机/室友用。**主机端零安装、不写注册表、不上驱动。**

本仓库是**针对 CampusBox 这个形态的特化固件工程**——不是通用 OpenWrt fork。它只做一件事：让一块 RV1106 板子成为「能被电脑当成网卡的校园网网关」。

> 当前版本：**v0.2**（2026-10-25 裁定：加 RJ45 / 不做 Win7 / 做 WiFi AP / 预算 200 元）。
> 形态也从「U 盘」改成「46×22×13mm 小方块 + USB 短尾巴」，因为 RJ45 座高 11.5mm。

## 为什么是「USB 网卡」而不是「帮用户设系统代理」

| | 托盘程序设系统代理 | CampusBox |
|---|---|---|
| 主机端 | 要装程序 | 零安装 |
| 驱动签名 | 需要（EV 证书年费数千） | **不需要**（NCM 系统内置） |
| 注册表 | 要写，被安全软件按进程树拦 | **不涉及** |
| 退出风险 | 不还原 = 整机断网 | 拔掉自动回退 WiFi |
| 覆盖协议 | 只有 HTTP/HTTPS | 全部（UDP/游戏/终端） |

## 架构

~~~text
PC ──USB(NCM)──┐
               │  usb0 192.168.7.1/24  ← DHCP + 劫持 DNS + tproxy
        ┌──────┴────────┐
        │    RV1106     │  mihomo(tproxy 7893) + dnsmasq + portal 认证
        │               │  hostapd(wlan1) 192.168.8.1/24（可选 AP）
        └──┬─────────┬──┘
           │ eth0    │ wlan0 (STA)
      DM9051/RJ45   校园 AP → 172.32.253.17 Portal
      （优先上行）
~~~

**上行状态机**：有网线且拿到 IP → 走 eth0；否则走 wlan0 STA；两者都不通 → 只有本地网段可通，面板上报警。切换是自动的，不重启。

手机/室友连 AP 时，流量同样过 tproxy，与 PC 一致；AP 默认 **10 分钟无客户端自动关闭**（省电省热）。

## 仓库结构

| 路径 | 职责 |
|---|---|
| `docs/HARDWARE-SPEC-v0.2.md` | **硬件技术规格书（21 章，给硬件同学）** |
| `docs/SW-HANDOVER.md` | 软件交接文档（本文档的姊妹篇） |
| `docs/INTERFACE-CONTRACT.md` | 软硬件接口契约（GPIO/分区/VID-PID/MAC） |
| `docs/DECISIONS-v0.2.md` | 四项裁定的推导与取舍（审计记录，实现以规格书为准） |
| `usb/` | libcomposite gadget（CDC-NCM） |
| `net/` | dnsmasq、nftables（DNS 劫持 + tproxy + 双接口）、策略路由 |
| `mihomo/` | 配置模板 + 订阅生成 + 余额读取 |
| `portal/` | Dr.COM 三步认证 + 探活退避 |
| `uplink/` | 上行状态机（有线优先）+ VBUS 三档降档 |
| `wifi/` | wpa_supplicant（STA）+ hostapd（AP）配置 |
| `panel/` | 状态页与 JSON 状态接口（供面板与产线治具读） |
| `imagebuilder/` | 固件配方（config.seed / packages.txt / rootfs-overlay） |
| `factory/` | 产线烧号与功能测试治具 |
| `tests/` | 上机冒烟测试 |

## 三条铁律（改代码前先读）

1. **只有一个 USB 配置（configuration）**。只做 CDC-NCM，不做 RNDIS 变体——同时暴露两种会让 Windows 偶发选错，表现为「插上没反应，拔了再插又好了」。
2. **校园网网段必须直连**。`172.32.0.0/16`、`10.0.0.0/8` 在 tproxy 规则里 return（无论从 usb0 还是 wlan1 进来）。一旦 Portal 认证流量被代理接管，全网瘫——这是本项目最容易复发的 bug。
3. **不加第二类 USB 接口**（MSC/HID/ACM）。配置与调试一律走 `http://192.168.7.1:8080`。

## 最小上手

~~~sh
make deps          # 检查 imagebuilder / 工具链
make config        # 从模板生成 mihomo 配置（需先填 uci 订阅）
make smoke         # 上机冒烟（需设备已插）
~~~

设备端命令（SSH 到 192.168.7.1）：

~~~sh
cb-start                 # 手动跑全链路启动（调试用）
/usr/sbin/panel-state    # 打印一行 JSON 状态
logread -f | grep cb-    # 看各子系统日志
~~~

## License

MIT
