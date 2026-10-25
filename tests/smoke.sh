#!/bin/sh
# 上机冒烟：验证「插上就是网卡」这件事成立（v0.2 增加上行与降档项）
set -u
G=${1:-192.168.7.1}
echo "== CampusBox 冒烟 v0.2 =="
printf '%-26s' "1 网关可达";        ping -c1 -W2 "$G" >/dev/null 2>&1 && echo OK || echo NG
printf '%-26s' "2 面板 8080";       curl -sf --max-time 5 "http://$G:8080/" >/dev/null && echo OK || echo NG
printf '%-26s' "3 DNS 劫持";        nslookup www.gstatic.com "$G" >/dev/null 2>&1 && echo OK || echo NG
printf '%-26s' "4 代理出口";        curl -s --max-time 12 -x "http://$G:7891" -o /dev/null -w '%{http_code}\n' https://api.openai.com/v1/models
printf '%-26s' "5 校园网直连";      curl -sf --max-time 5 "http://172.32.253.17/" >/dev/null 2>&1 && echo OK || echo "NG(可能正常)"
printf '%-26s' "6 上行状态";        curl -s --max-time 3 "http://$G:8080/api/state" | grep -o '"uplink":"[a-z0-9]*"' || echo NG
printf '%-26s' "7 VBUS / 档位";     curl -s --max-time 3 "http://$G:8080/api/state" | grep -o '"vbus_mv":[0-9]*,"power":"[a-z]*"' || echo NG
printf '%-26s' "8 有线吞吐(可选)";  echo "手动：iperf3 -c <有线对端>"
echo "提示：401 = 代理通（未带 key）／000 或 curl:(35) = 不通"
echo "      vbus <4600mV 且 power=mid/low 是正常降档，不是故障"
