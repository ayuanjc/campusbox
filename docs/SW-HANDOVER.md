# CampusBox 软件交接文档

**读者**：接下这份固件的人。假设你熟 OpenWrt / Linux 网络，但不熟这个项目。
**读法**：§1–§3 必须读（10 分钟）；§4–§8 是按需查的手册；§9 是你第一周该做的事。

---

## 1. 这个项目在做什么

一根 USB 棒，插到电脑上**多出一块网卡**（不是装软件、不是设代理）。棒子自己连校园 WiFi、自己过 Dr.COM Portal 认证、把流量按规则分流出去。拔掉，电脑自动回退原来的 WiFi。

```text
┌──────────┐   USB 2.0     ┌─────────────────────────────┐   WiFi STA   ┌──────────┐
│   PC     │◄─── NCM ─────►│        RV1106 (CampusBox)    │◄────────────►│ 校园 AP  │
│ 192.168.7.2│  (系统内置驱动)│ usb0 192.168.7.1/24         │  wlan0       │          │
└──────────┘               │  ├ dnsmasq   DHCP + option 6│              └──────────┘
                           │  ├ nft       劫持 53→1053   │                    │
                           │  ├ mihomo    1053 DNS       │                    ▼
                           │  │           tproxy 7893    │            172.32.253.17
                           │  ├ balance   读订阅余额     │              Portal
                           │  └ portal    三步认证       │
                           └─────────────────────────────┘
```

**主机端做了什么**：什么都没做。USB 枚举 → Windows 认出 CDC-NCM 网卡 → DHCP 拿到 192.168.7.2 → 网关 192.168.7.1 → Windows 按链路速度算路由 metric（USB 网卡 25–35，WiFi 50–65）→ 默认路由自动切到 usb0。

**为什么不是「帮用户设系统代理」**：那条路已死。未签名程序写 HKCU Internet Settings 会被安全软件按**进程树**拦（WinError 5），代码绕不过，退出不还原就是整机断网。改用 USB 网卡后，这些全部消失：不碰注册表、不要驱动签名、不要安装、拔了就恢复。

---

## 2. 三条铁律

违反任何一条，产品在真实环境里就是「时好时坏」，而且极难定位。

| # | 铁律 | 违反后的症状 |
|---|---|---|
| 1 | **只暴露一个 USB configuration**（只 NCM，或只 RNDIS） | Windows 偶发选错驱动：「插上没反应，拔了再插又好」 |
| 2 | **校园网网段必须 return，不进代理** | Portal 认证流量被 tproxy 吃掉 → 认证失败 → 全网瘫（本项目最容易复发的 bug） |
| 3 | **不加第二类 USB 接口**（MSC/HID/ACM） | MSC 触发 Windows 自动播放；多接口改描述符会打乱驱动匹配 |

铁律 2 的代码位置：`net/nftables-usb0.nft` 的 chain pre 第一条规则，以及 `mihomo/config.tmpl.yaml` 的 `IP-CIDR,172.32.0.0/16,DIRECT` 与 `fake-ip-filter`。**三处都要有**，缺一处就漏。

---

## 3. 你必须知道的平台事实

| 事实 | 数值 / 行为 | 为什么要记住 |
|---|---|---|
| 网段 | `192.168.7.0/24`（**冻结**，不许改） | 改了以后所有文档、治具、面板、用户手册全废 |
| 设备地址 | `192.168.7.1` | 面板 8080 / 代理 7891 / DNS 53 |
| DHCP 池 | `.10`–`.50`（`.51`–`.99` 预留） | 预留段给未来多设备/有线 |
| DNS | usb0:53 → **nft 重定向** → mihomo:1053 | 所以 dnsmasq 必须 `port=0`，否则抢 53 打起来 |
| tproxy | 7893 + fwmark 1 + table 100 | 缺 table 100 的 local 路由 = 所有 TCP 半开 |
| 面板 | 8080，读 `/api/state` | 治具也读它，**不靠肉眼看 LED** |
| 内存 | 256MB 是下限，128MB 必 OOM | 预算已算到 253MB（见规格书 21.1） |
| 存储 | eMMC ≥4GB，7 个分区 | 128MB flash 装不下双 rootfs |
| 判据 | 代理通 = `curl -x http://192.168.7.1:7891 https://api.openai.com/v1/models` 返回 **401** | 401 表示链路通但没带 key；`000`/`curl:(35)` = 不通 |

---

## 4. 代码地图

```text
usb/           gadget 定义（谁让 PC 看到网卡）
net/           地址分配 + 分流规则（谁决定哪些包走代理）
mihomo/        代理内核与订阅（谁真正转发）
portal/        校园认证（谁保住上行不断）
panel/         状态呈现（人看什么）
factory/       产线（工厂怎么验）
imagebuilder/  出固件（怎么打包）
tests/         冒烟（改完怎么确认没坏）
```

### 4.1 启动顺序（改任何一步前先看这张图）

`rootfs-overlay/usr/sbin/cb-start` 按顺序执行，**每一步独立兜底**（前一步失败不阻断后面，日志记一行继续）：

```text
1. gen-config.sh   → 生成 /etc/cb/config.yaml（订阅 → proxy-providers）
2. gadget-ncm.sh   → configfs 建 gadget → UDC 上线 → usb0 起 IP
3. dnsmasq         → usb0 上发 DHCP（port=0，不解析）
4. tproxy-up.sh    → ip rule/route + nft + ip_forward
5. mihomo -d       → DNS 1053 + tproxy 7893
6. uplink          → wlan0 连校园 AP
7. balance.sh      → 每 3 分钟刷新余额（循环）
8. portal-probe.sh → 20s 探活，失败重认证（循环）
```

顺序不能乱的两个原因：
- **gadget 必须在 dnsmasq 之前**：usb0 不存在时 dnsmasq 会 `bind-dynamic` 失败并退出。
- **nft 必须在 mihomo 之前**：tproxy 目标端口没人监听时，包被丢掉，PC 表现为「网卡正常但什么都打不开」，比不配还难查。

### 4.2 每个文件干什么

| 文件 | 一句话 |
|---|---|
| `usb/gadget-ncm.sh` | libcomposite 建 NCM：VID 0x1d6b / PID 0x0104 / MaxPower 250(=500mA) / dev_addr 02:aa:bb:cc:dd:01 |
| `usb/gadget-rndis.sh` | Win7 SKU 专用，PID 0x0105。**不要和 NCM 同时存在** |
| `net/dnsmasq-usb0.conf` | interface=usb0 / dhcp-range .10-.50 / option 3,6 = 192.168.7.1 / port=0 |
| `net/nftables-usb0.nft` | chain dns 劫持 53；chain pre 先 return 校园网段再 tproxy；chain fwd + masquerade |
| `net/tproxy-up.sh` | `ip rule add fwmark 1 lookup 100` + `ip route add local default dev lo table 100` + `nft -f` + ip_forward |
| `mihomo/config.tmpl.yaml` | 模板：`@@SUBS@@` 订阅块、`@@SECRET@@` 控制器口令 |
| `mihomo/gen-config.sh` | `/etc/cb/subs.txt` 每行一条 → sub1..sub6 provider；secret = urandom 16 hex |
| `mihomo/balance.sh` | `curl -sI` 读 `subscription-userinfo` 响应头 → `/run/cb/state.json` |
| `portal/campus-auth.sh` | 三步 Dr.COM；**全程 `--noproxy '*'`** |
| `portal/portal-probe.sh` | 20s 探 `generate_204`，失败重认证，指数退避到 120s |
| `rootfs-overlay/usr/sbin/cb-start` | 上面那个 8 步 |
| `rootfs-overlay/etc/init.d/campusbox` | procd respawn 3600 5 0 |
| `panel/state.sh` | 输出一行 JSON（link/usb0/mihomo/serial/balance） |
| `panel/index.html` | 深色状态页，3s 轮询 `/api/state` |
| `factory/provision.sh` | CSV → uci serial + `/factory/mac_usb0`、`/factory/mac_wlan` |
| `factory/test-jig.sh` | T1–T6 判定 |
| `tests/smoke.sh` | 5 项上机冒烟 |

---

## 5. 五个关键机制（原理 + 为什么这么写）

### 5.1 gadget：为什么 LibreNCM 而不是 RNDIS

| | NCM | RNDIS |
|---|---|---|
| Win10 1809+ / Win11 | 内置 | 内置 |
| macOS / Linux | 内置 | macOS 不认 |
| 驱动签名 | 不需要 | 不需要 |
| Win7 | 不支持 | 支持 |

选 NCM 的前提是「只服务 Win10 1809 以上」。如果哪天要支持 Win7，做法是**另一个固件 SKU**（改 PID 0x0105 + 换成 rndis.usb0 函数），不是同一个固件里塞两个配置。

Linux 侧多接口是自动的：`functions/ncm.usb0` 一个函数会生成「控制接口 + 数据接口」，不需要手工描述符。

**枚举失败排查表**见规格书 §7.7（7 行：主机没反应 / 设备管理器黄色感叹号 / 出现未知设备 / 反复断开重连 / 只能看到一个接口 / Windows 显示「未识别的网络」 / 有时能有时不能）。

### 5.2 tproxy：为什么不是 redirect（REDIRECT/TPROXY 的区别）

`REDIRECT`（nat 表）只改目标端口，**拿不到原始目标地址**，而且是 NAT 语义——只适合 HTTP。`TPROXY`（mangle 表）保留原始目标地址并打 mark，配合 `ip rule fwmark` 把包送回本机协议栈。UDP（DNS/QUIC/游戏）只有 TPROXY 能处理。

三个必要条件，缺一个就「通则不通」：
1. `nft ... tproxy to :7893 meta mark set 1`（打标）
2. `ip rule add fwmark 1 lookup 100`（把带标包导向 table 100）
3. `ip route add local default dev lo table 100`（table 100 说「这些包是给本机的」）

**踩过的坑**：忘了第 3 条时，包会被当转发包送回 wlan0，形成环路，表现为「网络时断时续，日志里一堆 ttl exceeded」。

### 5.3 Portal：为什么必须 `--noproxy`

认证的三步请求（`PortalJsonAction.do?viewStatus=1` → `quickauth.do` → 必要时 `quickauthdisconn.do`）打的是 `172.32.253.17`，这是**局域网地址**。如果这些请求经过 mihomo，会：
1. 命中 `GEOIP,CN,DIRECT` 或 `IP-CIDR,172.32.0.0/16,DIRECT` —— 看起来没事；
2. 但 DNS 走 fake-ip 时域名解析成 198.18.x.x，认证域名被 fake-ip 吃掉 → 拿到假 IP → 认证必然失败。

所以**两道保险**：nft 里 return + shell 里 `--noproxy '*'`。原来的 Windows 版在 Python 里用 `ProxyHandler({})` 解决同一个问题，坑是一样的。

参数来源：`wlanuserip`/`mac`/`wlanacname`/`vlan` 正常从 302 重定向 URL 里采集；抓不到就用本机 `ip addr` + `/sys/class/net/*/address` 兜底。`authByRas=false` 意味着密码明文提交（`listpasscode=0` 无验证码）——这是校方 Portal 的实现，不是我们的选择。

### 5.4 余额：为什么自己算

mihomo 不解析 `subscription-userinfo` 响应头。所以 `balance.sh` 每 3 分钟对所有订阅 `curl -sI`：

```text
subscription-userinfo: upload=123; download=456; total=1099511627776; expire=...
```

把 upload+download+total 求和后写 `/run/cb/state.json`。面板只读这个 JSON，所以**换订阅格式不用改面板**。

多订阅合并（Windows 版的「合并模式」）：这里不需要记账代码。mihomo 的 url-test 组 `use: [sub1..sub6]` 会在某条耗尽/故障时自然跳过，**天然无缝**。

### 5.5 AI 分组：为什么要探真实端点

`url: https://api.openai.com/v1/models` 而不是 `gstatic/generate_204`。因为 **gstatic 通 ≠ openai 通**：香港节点对 gstatic 全通，但对端会按出口 IP 直接断 TLS（`SSL: UNEXPECTED_EOF_WHILE_READING`）。用真实端点探测 + `filter` 排除香港，才是有效判据。

判据沿用：代理通 = 返回 401（未带 key）；`000` / `curl:(35)` = 不通。

---

## 6. 开发环境

### 6.1 没有硬件时怎么开发

| 目标 | 做法 |
|---|---|
| 验证 gadget 脚本 | 任意有 USB device 口的 Linux（树莓派 / Pi Zero）跑 `usb/gadget-ncm.sh`，插到 Windows 看是否多一块网卡 |
| 验证 nft/tproxy | 一台 Linux 虚拟机 + 第二个网卡模拟 usb0，把 `iifname usb0` 换成实际网卡名 |
| 验证 mihomo 配置 | 本机跑 mihomo，`-d` 指到含 config.yaml 的目录，先 `-t` 测配置 |
| 验证面板 | 直接 `python -m http.server` 起 `panel/`，`/api/state` 用假 JSON |
| 验证 Portal 脚本 | 在校园网内的任意 Linux 上跑（`sh -x` 看三步请求） |

**不建议**在没有硬件时写「模拟整个系统」的测试框架——真机的坑（USB 枚举时序、DHCP 竞争、WiFi 掉线）模拟不出来，成本还高于买一块核心板（150 元）。

### 6.2 日志在哪

| 日志 | 位置 |
|---|---|
| 启动串 | `/data/logs/cb.log` |
| mihomo | 同 `cb.log`（`-d /etc/cb` 输出重定向） |
| 当前链路状态 | `/run/cb/link`（online / offline(code)） |
| 余额 | `/run/cb/state.json` |
| 内核 | `dmesg`（USB 枚举、掉电、WiFi 断连都在这里） |

`/data` 是独立分区（1GB），**重启不丢**——排查偶发问题必须靠它，所以别把日志写 `/tmp`。

### 6.3 常见故障 → 先查什么

| 症状 | 先查 |
|---|---|
| PC 插上没反应 | `dmesg` 有无 gadget 注册；`ls /sys/class/udc` 有无控制器；UDC 是否被写了 |
| 有网卡但拿不到 IP | dnsmasq 是否在跑；`port=0` 是否被改；usb0 是否有 192.168.7.1 |
| 能 ping 网关但打不开网页 | nft 规则是否 load（`nft list table ip cb`）；mihomo 7893 是否 listen |
| DNS 超时 | mihomo 1053 是否 listen；`fake-ip-filter` 是否把域名吃了 |
| 校园认证反复失败 | 是否走了代理（`--noproxy`）；Portal 地址是否变；MAC 是否被绑 |
| 一切正常但很慢 | WiFi 信号 / 节点 RTT；usb0 是否掉到 12Mbps（USB 供电不足的征兆） |
| 隔几小时断一次 | WiFi 漫游 / Portal 超时踢线；看 `/run/cb/link` 历史 |

---

## 7. 变更风险清单（改这些地方会炸）

| 位置 | 风险 | 加固方式 |
|---|---|---|
| `192.168.7.0/24` | 全网段冻结，改了等于换产品 | 只允许在规格书层面讨论 |
| `nftables` 的 return 规则 | 删了 Portal 立刻瘫 | 任何 nft 改动必须跑 `tests/smoke.sh` 第 5 项 |
| `fake-ip-filter` | 加错域名 → 该域名被解析成假 IP | 加域名前先 `nslookup` 验证 |
| `MaxPower` (250) | 调大 → 主机触发电涌保护；调小 → WiFi 发射掉压重启 | 保持 250，改电源硬件 |
| USB 配置数量 | 加第二个 configuration → Windows 偶发选错 | 一个固件一个配置 |
| 分区表 | 重分区要动 bootloader，产线事故 | 规格书 §21.4 已冻结 |
| `gen-config.sh` 的 secret | 固定 secret = 控制器裸奔 | 保持 urandom |
| 面板暴露 0.0.0.0 | 同网段任何人可看余额（含订阅信息） | 面板只绑 usb0，或加 token |

---

## 8. 尚未完成 / 待决策

| 项 | 状态 | 说明 |
|---|---|---|
| `/api/state` 的 HTTP 服务 | **未实现** | `panel/state.sh` 只输出 JSON；需要一个最小 HTTP 服务（uhttpd 或 `socat`/`busybox httpd` + CGI）把它接到 8080。建议 `busybox httpd -f -p 8080 -h /www` + CGI 脚本调 state.sh |
| wlan0 连 WiFi 的完整实现 | **未实现** | `cb-start` 里只有 `wpa_cli add_network` 占位；需要按 uci `uplink.ssid/key` 调 `wpa_cli set_network 0 ssid/key` 并 `enable` |
| 订阅耗尽自动切换提示 | 未做 | 现在靠 url-test 自然跳过，但用户看不到「哪条耗尽了」 |
| 恢复分区（rootfs_b）切换逻辑 | 未做 | 分区已预留，A/B 切换脚本未写（建议参考 OpenWrt `sysupgrade -r` + 双分区标记） |
| OTA | 未做 | 建议 A/B + 校验 + 回滚标记，不要原地刷 |
| mDNS `campusbox.local` | 预留 | 规格书 §21.7.3 提到，未实现 |
| 面板鉴权 | 未做 | 见 §7 风险表 |
| Windows 侧托盘工具 | **不做** | 形态决策：设备自足，托盘不是必需。若要做，只做「发现设备 → 显示余额/节点 → 打开面板」，一行注册表都不写 |

---

## 9. 接手第一周清单

```text
Day 1  读完 §1–§3；跑 make deps；对现有 30 个文件做一遍通读（每文件 1 分钟）
Day 2  买/借一块 RV1106 核心板（或 Pi Zero 2 W），只跑 usb/gadget-ncm.sh，
       插到 Win11 上确认「多出一块网卡 + 自动拿到 192.168.7.2」
       ← 这是全项目最危险的假设，先证伪再写其它代码
Day 3  在板子上装 mihomo，跑 net/ + mihomo/，确认 PC 能通过 7891 出去
Day 4  在校园网内跑 portal/campus-auth.sh，确认能认证上
Day 5  补 §8 前两项（/api/state HTTP + wlan0 连接），跑通 tests/smoke.sh 全绿
Day 6+ 出第一版 imagebuilder 镜像
```

**如果你只有一天**：做 Day 2。它决定这个产品到底成不成立。

---

## 10. 与硬件文档的关系

| 文档 | 内容 | 谁看 |
|---|---|---|
| `docs/HARDWARE-SPEC-v0.1.md` | 21 章：产品定义 / 选型 / 电源 / 热 / 结构 / 原理图 / PCB / BOM / 产测 / 认证 / 路线 / 风险 | 硬件同学 |
| `docs/INTERFACE-CONTRACT.md` | 软硬件握手：GPIO 表、分区表、iSerial、MAC、LED/按键语义、时序 | 双方签字用 |
| `docs/SW-HANDOVER.md` | 本文档 | 软件接手人 |

规格书 §21 的「15 项冻结检查表」是硬件设计的验收门；本文件 §3 的平台事实表是软件实现的验收门。**两边都签过，项目才能进 v1.0。**
