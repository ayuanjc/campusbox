# 软件交接文档 — CampusBox v0.2

> 面向：接手这份固件代码的人（可能是三个月后的你）。
> 姊妹文档：`docs/HARDWARE-SPEC-v0.2.md`（硬件规格书，21 章），`docs/INTERFACE-CONTRACT.md`（软硬件接口契约）。
> 版本：v0.2（2026-10-25）—— 相对 v0.1 的主要变化是**加了 RJ45 有线上行**与**WiFi AP 模式**，两者都改了架构而不是加功能，所以本文是重写的，不是打补丁。

---

## 0. 一句话说清这个产品

**一根带短尾巴的小方块插到电脑 USB 口上，电脑就多出一块网卡。这块网卡后面站着一个自己会连校园网、自己会过 Portal 认证、按规则分流的 Linux 小主机。**

用户视角：
1. 插上 → Windows 弹出「已连接 CampusBox」→ 能上网，且已经翻好墙。
2. 拔掉 → 自动回到原来的 WiFi，什么都没改过。

工程师视角：一个 RV1106 上跑 OpenWrt，用 USB gadget 把自己的以太网口「假装成」一块 USB 网卡（CDC-NCM），PC 侧零安装、零注册表、零驱动签名。

---

## 1. 为什么不是「托盘程序帮你设系统代理」

这条路走过，失败了。**根因不是代码，是安全软件的进程树拦截**：

- 未签名程序写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` 会被火绒按进程树拦下，报 `PermissionError [WinError 5]`；
- 同一进程树派生的 `reg.exe` 一样被拒；
- WinINET option 75 设置后返回 TRUE，但读回来还是 DIRECT —— 静默失败，最难查的那种；
- 退出时没还原 = 用户整机断网，这是**事故级**的售后。

**换形态解决的是同一件事的不同层面**：不再是「改系统设置」，而是「变成系统的网络设备」。系统对 USB 网卡的态度和对注册表写入完全不同——前者是硬件枚举，后者是安全边界。

---

## 2. 数据流（v0.2，含 AP 与有线上行）

```text
                        ┌──────────────────────────────┐
   PC ──USB(NCM)── usb0 │  dnsmasq   192.168.7.1/24     │
  手机 ──WiFi──── wlan1 │  dnsmasq   192.168.8.1/24（AP，可选）
                        │                              │
                        │  nft: 两接口 53 → :1053       │
                        │       其余 tproxy → :7893     │
                        │       mark 1 → table 100      │
                        │                              │
                        │  mihomo: 7891 mixed / 7893 tproxy / 9090 ctl
                        └──────┬──────────────┬────────┘
                          eth0 │              │ wlan0
                     DM9051/RJ45          校园 AP
                     （优先上行）      → 172.32.253.17 Portal
```

**上行选择是自动的**（`uplink/uplink-watch.sh`）：有网线拿到 IP 就走 `eth0`（metric 10），否则走 `wlan0`（metric 20）。判据不是「接口 up」——墙口经常有 link 却没有 DHCP、没有 Portal 放行。所以只看「有没有地址」。

**为什么有线优先**：设备自己过 Portal 认证会占用校园账号，而校园网的账号是单点在线——设备认证会把 PC 踢下线。走有线时设备用的是网口自己的 DHCP/IP（或另一个人账号），**完全不碰 PC 正在用的那个 WiFi 账号**，从根上消除互踢。

---

## 3. 三条铁律（改代码前先读）

| # | 铁律 | 违反了会怎样 | 在哪实现 |
|---|---|---|---|
| 1 | **只有一个 USB 配置**。只做 CDC-NCM，不做 RNDIS 变体 | Windows 偶发选错配置 → 「插上没反应，拔了再插又好了」，偶发且不可复现 | `usb/gadget-ncm.sh` |
| 2 | **校园网网段必须 return**，无论从 usb0 还是 wlan1 进来 | Portal 认证流量被代理吃掉 → 认证死循环 → 全网瘫。这是本项目最容易复发的 bug | `net/nftables-cb.nft` 的 `$LAN` 定义 |
| 3 | **不加第二类 USB 接口**（MSC/HID/ACM） | MSC 触发 Windows 自动播放；多接口改描述符会让驱动匹配出错 | 同上，只声明 2 个接口 |

---

## 4. 启动顺序（cb-start，8 步）

```sh
sh /etc/cb/gen-config.sh     # 0 从 uci 生成 mihomo 配置
sh /etc/cb/gadget-ncm.sh     # 1 建 usb0（必须先有接口）
dnsmasq --conf-file=…usb0    # 2 DHCP
sh /etc/cb/tproxy-up.sh      # 3 ip rule + nft（必须早于 mihomo）
mihomo -d /etc/cb            # 4 代理内核
sh /etc/cb/uplink-watch.sh & # 5 上行状态机（长驻）
dnsmasq …wlan1 + hostapd     # 6 AP（uci 开关，可选）
sh /etc/cb/vbus-governor.sh & # 7 电源降档（必须在 WiFi 起来后）
sh /etc/cb/balance.sh & …    # 8 余额 + Portal 探活
```

**两个硬依赖，顺序错了会静默失败**：

1. **gadget 必须早于 dnsmasq**：`bind-dynamic` 在接口不存在时绑不上，dnsmasq 直接退出，症状是「PC 拿到 169.254 自分配地址」。
2. **nft 必须早于 mihomo**：反过来的症状是 mihomo 起来时 tproxy 端口没人接，但规则已经生效，首批连接全超时——你会以为是节点问题。

每一步都是**独立兜底**：前一步失败只写日志，不中断后面。宁可半残（只有 DNS 没代理）也不要整机黑屏，因为用户看不到日志，只看得到「能不能上网」。

---

## 5. 七个机制为什么这么设计（都是踩过坑换来的）

### 5.1 CDC-NCM 而不是 RNDIS

| | NCM | RNDIS |
|---|---|---|
| Win10 1809+ / Win11 / macOS 12+ / Linux 5.15+ | **内置驱动** | 内置 |
| Win7 | 不支持 | 支持 |
| 结论 | **选它** | v0.2 起不管 Win7，删掉 |

NCM 是 USB-IF 标准（CDC 类 0x0D），RNDIS 是微软私有。既然不做 Win7，就没有任何理由碰 RNDIS。

### 5.2 TPROXY 而不是 REDIRECT

`REDIRECT` 只能劫 TCP，UDP（游戏、QUIC、部分 DNS）直接漏过去；`TPROXY` 保留原始目的地址，TCP/UDP 通吃。

**但 TPROXY 有个必踩的坑**：策略路由表里必须有 `ip route add local default dev lo table 100`。少了这一条，包会被送回主路由表形成环路，症状是「一发请求就超时，`top` 看 CPU 却很低」——因为包在内核里转圈，不到用户态。

### 5.3 Portal 认证必须 `--noproxy`

mihomo 开了 fake-ip，域名会被解析成 `198.18.x.x`。Portal 认证请求如果走域名，会打到假 IP 上，认证必然失败，而且报错很像是「服务器拒绝」。

所以 `portal/campus-auth.sh` 里所有 curl 都带 `--noproxy '*'`，并且直连 `172.32.253.17`（Portal 的 IP，不是域名）。

这是 Windows 版 Clash 那个 `ProxyHandler({})` 坑的等价物，换到 Linux 上换了形式，本质一样：**认证流量绝不能进代理**。

### 5.4 余额要自己算

mihomo 的 `subscription-userinfo` 响应头它**不解析**。想显示「剩余 569 GB」只有两条路：自己 curl 订阅地址读头，或者不做。

`mihomo/balance.sh` 每 3 分钟 `curl -sI` 一次订阅地址，把 `upload/download/total/expire` 算成 `/run/cb/state.json`。面板的「长条」一行代码都不用改，只换 fetch 目标。

**顺带好处**：6 条订阅可以做成 6 个 `proxy-providers`，全部塞进一个 `url-test` 组。哪条耗尽，健康检查自动跳过，**不需要写「记账切回」的逻辑**——v0.1 的 Windows 版是自己记节点名再切回来，那是没必要的复杂度。

### 5.5 AI 分组要探真实端点

原版用 `https://www.gstatic.com/generate_204` 做健康检查，结果：香港节点 gstatic 全通，但 openai 全不通（对端按出口 IP 断 TLS，报 `SSL: UNEXPECTED_EOF_WHILE_READING`）。

所以 AI 组的 `url` 直接写 `https://api.openai.com/v1/models`，再用 `filter` 排除香港节点。**判读规则**：

| 返回 | 含义 |
|---|---|
| `401` | 通（没带 key，正常） |
| `000` / `curl:(35)` / 超时 | 不通 |
| `0.1s` 就断 | 本机或边缘拦截 |
| `dial tcp i/o timeout` | 节点端口不通 |

### 5.6 VBUS 三档软降档（v0.2 新增，这是本版最重要的机制）

**问题**：AP 模式满功率时 3.3V 峰值 830mA → 5V 侧 **644mA**，超 USB 2.0 标称 500mA **29%**。主机不会告诉你它撑不撑得住，只会「掉压复位」或「过流保护」。

**做法**：VBUS 经 1/3 分压进 ADC0，`uplink/vbus-governor.sh` 每秒采样：

| VBUS | 档位 | SoC | WiFi | 估算功率 |
|---|---|---|---|---|
| ≥ 4.75V | full | 800MHz | 18dBm | 1.2W |
| 4.60–4.75V | mid | 700MHz | 15dBm | 1.0W |
| 4.40–4.60V | low | 600MHz | 12dBm | 0.9W |
| 连续 3 次 < 4.40V | safe | 600MHz | 12dBm + **关 AP** | 保命 |

**降档不是省电优化，是热设计与电流设计的必要条件**：46×22×13 铝壳在 0.9W 下壳温 48°C（合格），1.2W 下 55–62°C（勉强），满功率 1.4W 下 60–68°C（不合格）。

### 5.7 上行状态机（v0.2 新增）

`uplink/uplink-watch.sh` 每 10 秒判一次，切换用 `ip route replace` 而不是「先断后连」——避免切换瞬间出现无路由的真空期（玩家会发现「打游戏时偶尔卡一下」，那就是这个真空）。

WiFi 连接那段要格外小心：`wpa_cli add_network` 的返回值是网络 id，但**第一次调用会返回 `FAIL`**（还没 add 过），所以要 `||true` 再取 `tail -1`。这个坑我在 Windows 版里踩过一次。

---

## 6. 硬件还没到，怎么开发

| 你想要验证的 | 用什么代替 | 局限 |
|---|---|---|
| USB 网卡枚举 | **Raspberry Pi Zero 2 W** + `g_ncm` 或 `libcomposite` | 100 元，一天能跑通；PC 侧行为与最终产品一致 |
| 分流与 tproxy | 任意 Linux 虚拟机（Ubuntu 22.04） | 无 USB gadget，但 nft/mihomo/dnsmasq 部分完全可测 |
| Portal 认证 | 校园网内任意一台机器跑 `portal/campus-auth.sh` | 真环境，逻辑完全一致 |
| 面板与状态机 | 虚拟机上直接跑 `panel/state.sh` | — |
| 电源降档 | 可调电源 + 万用表模拟 VBUS | 只能验逻辑，验不了真实掉压波形 |

**唯一必须等硬件的**：真实功耗与壳温、USB 枚举在各类主机上的兼容性（尤其是 USB3 hub 与老主板）。

---

## 7. 文件地图与日志位置

| 设备路径 | 内容 | 来源 |
|---|---|---|
| `/etc/cb/` | 全部运行脚本（gadget/nft/mihomo/portal/uplink/wifi） | `make stage` 装配 |
| `/etc/config/campusbox` | 全部可配置项（portal 账号、uplink SSID/PSK、AP 开关、ADC 参数、端口） | uci |
| `/usr/sbin/cb-start` | 启动总控 | rootfs-overlay |
| `/usr/sbin/panel-state` | 一行 JSON 状态（产线治具读它，不靠肉眼看 LED） | panel/state.sh |
| `/data/logs/cb.log` | 全部子系统日志（每个都带前缀：`gadget/nft/mihomo/uplink/vbus/ap/portal`） | 运行时 |
| `/run/cb/*.state`, `vbus.mv`, `state.json` | 当前状态快照 | 运行时 |

**日志按前缀 grep，别 tail 全量**：

```sh
logread -f | grep ' vbus: '      # 电源降档
logread -f | grep ' uplink: '    # 上行切换
logread -f | grep ' portal: '    # 认证
```

---

## 8. 排障对照表

| 现象 | 最可能的原因 | 查什么 |
|---|---|---|
| 插上 PC 没反应，设备管理器无新设备 | gadget 未生效 / UDC 未绑定 | `ls /sys/class/udc`；`cat /sys/kernel/config/usb_gadget/cb/UDC` |
| PC 认成网卡但拿到 169.254.x.x | dnsmasq 未起（多因 usb0 不存在时先起了） | `logread | grep dnsmasq`；重跑 `cb-start` |
| 能上网但很慢，CPU 却很低 | tproxy 环路了（table 100 缺 local default） | `ip route show table 100` |
| Portal 认证一直失败 | 认证流量进了代理（fake-ip） | `curl --noproxy '*' -v http://172.32.253.17/` |
| 认证成功但一分钟后又掉 | 端口 53 被劫持到假 IP，认证心跳走域名 | nft 的 `$LAN` 里加上 Portal 域名/网段 |
| 手机连 AP 能连上但打不开网页 | dnsmasq-wlan1 没起 / wlan1 不在 nft 的 `$CLI_IFS` 里 | `ip addr show wlan1`；`nft list table ip cb` |
| 满速跑一会儿就断电重启 | VBUS 掉压，降档没生效 | `cat /run/cb/vbus.mv /run/cb/vbus.state` |
| 有线插着还是走 WiFi | eth0 没拿到地址，状态机判定不可用 | `ip -4 addr show eth0`；`cat /run/cb/uplink.state` |
| 面板 8080 打不开 | web 服务没起（v0.2 仍是未完成项） | 见 §9 |

---

## 9. v0.2 未完成清单（诚实版）

| # | 项 | 影响 | 难度 |
|---|---|---|---|
| 1 | **8080 面板的 HTTP 服务**（缺 busybox httpd + CGI 包装） | 面板与产线治具都读不到 `/api/state` | 半天 |
| 2 | **Mihomo 配置里 6 条订阅的真实地址**（`/etc/cb/subs.txt` 未填） | 没有节点 | 用户填 |
| 3 | **A/B 分区恢复切换**（rootfs_b 存在但没人切） | 固件升级失败会变砖 | 2 天 |
| 4 | **OTA**（现在只能 `make push` 手工推） | 无法远程修复 | 3 天 |
| 5 | **订阅耗尽提示**（只显示剩余，不主动提醒） | 用户被断网才发现 | 半天 |
| 6 | **mDNS**（`campusbox.local`） | 用户得记 IP | 半天 |
| 7 | **面板鉴权**（现在无密码，同网段谁都能看） | 宿舍环境可接受 | 半天 |
| 8 | **802.11 信道自动选择**（hostapd 写死 channel 6） | 宿舍信道拥堵时 AP 慢 | 1 天 |
| 9 | **多 PC 同时插入同一台设备**（现在只支持 1 个 usb0） | 超出产品定义 | — |

**明确不做**：Windows 托盘程序。形态决定不需要，做了就是回到老路上。

---

## 10. 接手第一周

| 天 | 做什么 | 为什么 |
|---|---|---|
| D1 | 通读本文 + 硬件规格书 §1 §2 §21；跑 `make deps && make stage` 看装配结果 | 建立全局图，知道哪些文件是「生成」的 |
| **D2** | **买 RV1106 核心板（或 Pi Zero 2 W），只做一件事：让 Windows 把它认成网卡** | **这是整个项目唯一的高风险假设。150 元一天能证伪，比画完 4 层板才发现便宜两个数量级** |
| D3 | 在虚拟机上跑通 nft + mihomo + dnsmasq，用 `tests/smoke.sh` 前 5 项自测 | 无硬件也能验证 80% 的软件逻辑 |
| D4 | 把 `portal/campus-auth.sh` 在你真实的校园网里跑通 | Portal 是外部依赖，越早跑越好 |
| D5 | 补 §9 的 1、5、6 三项（都是半天活） | 让面板真正可用 |
| D6–D7 | 接硬件后测功耗与壳温，验证三档降档门限 | 门限值现在是算出来的，不是测出来的 |

---

## 11. 与硬件文档的关系

- **规格书是需求**，本文是实现。两者冲突时以规格书为准（它记录的是「为什么这么定」）。
- 规格书 §21 是「给软件留空间」的硬要求清单，本文 §5.6/§5.7 的两个新机制（VBUS ADC、上行状态机）都依赖它：**VBUS 分压进 ADC0** 是 §21.11 检查表第 16 项，**RJ45 座高** 是第 17 项。
- 接口契约（`INTERFACE-CONTRACT.md`）里任何一项变了（VID/PID、iSerial 格式、GPIO 分配、分区表），本文对应章节都要跟着改——反之亦然。

---

## 附录：v0.2 相对 v0.1 的软件侧变化

| 变化 | 文件 |
|---|---|
| 新增有线上行状态机 | `uplink/uplink-watch.sh` |
| 新增 VBUS 三档降档 | `uplink/vbus-governor.sh` |
| 新增 AP 模式（hostapd + 第二 dnsmasq + 自动关） | `wifi/hostapd.conf`, `wifi/ap-autoclose.sh`, `net/dnsmasq-wlan1.conf` |
| nft 改双客户端接口 + 双上行 | `net/nftables-cb.nft`（旧 `nftables-usb0.nft` 已删） |
| 删除 RNDIS | 删 `usb/gadget-rndis.sh` |
| 新增装配步骤（脚本进 `/etc/cb`） | `tests/stage.sh`, `Makefile` |
| 状态接口扩展 uplink/vbus/power/ap_clients | `panel/state.sh` |
| 冒烟测试扩展 3 项 | `tests/smoke.sh` |
