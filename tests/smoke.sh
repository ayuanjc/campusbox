#!/bin/sh
# 上机冒烟：验证「插上就是网卡」这件事成立
set -u
G=${1:-192.168.7.1}
echo "== CampusBox 冒烟 =="
printf '%-24s' "1 网关可达";      ping -c1 -W2 "$G" >/dev/null 2>&1 && echo OK || echo NG
printf '%-24s' "2 面板 8080";     curl -sf --max-time 5 "http://$G:8080/" >/dev/null && echo OK || echo NG
printf '%-24s' "3 DNS 劫持";      nslookup www.gstatic.com "$G" >/dev/null 2>&1 && echo OK || echo NG
printf '%-24s' "4 代理出口";      curl -s --max-time 12 -x "http://$G:7891" -o /dev/null -w '%{http_code}\n' https://api.openai.com/v1/models
printf '%-24s' "5 校园网直连";    curl -sf --max-time 5 "http://172.32.253.17/" >/dev/null 2>&1 && echo OK || echo "NG(可能正常)"
echo "提示：401 = 代理通（未带 key），000/35 = 不通"
