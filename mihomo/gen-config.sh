#!/bin/sh
# 从 uci 读订阅列表 → 生成 mihomo 配置。订阅地址存 /etc/cb/subs.txt（每行一条）。
set -e
CB=/etc/cb
TPL=$CB/config.tmpl.yaml
OUT=$CB/config.yaml
SUBS=$CB/subs.txt
[ -f "$SUBS" ] || { echo "缺 $SUBS"; exit 1; }

n=0
: > $CB/.subs.frag
while IFS= read -r url; do
  [ -z "$url" ] && continue
  case "$url" in \#*) continue;; esac
  n=$((n+1))
  [ $n -gt 6 ] && break
  cat >> $CB/.subs.frag <<EOF
  sub$n:
    type: http
    url: "$url"
    interval: 10800
    path: ./providers/sub$n.yaml
    health-check: { enable: true, url: "http://www.gstatic.com/generate_204", interval: 300 }
EOF
done < "$SUBS"

SECRET=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)
sed -e "s|@@SUBS@@|$(cat $CB/.subs.frag | sed 's/[&|]/\\&/g')|" \
    -e "s|@@SECRET@@|$SECRET|" "$TPL" > "$OUT"
echo "$SECRET" > $CB/.secret
echo "生成 $OUT（$n 个 provider）"
