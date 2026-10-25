#!/bin/sh
# 把装配好的 overlay 推到已连接设备（研发期用；正式发布走 imagebuilder）
G=${1:-192.168.7.1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sh "$ROOT/tests/stage.sh" >/dev/null
tar -C "$ROOT/build/stage" -cf - . | ssh root@$G "tar -xf - -C / && /etc/init.d/campusbox restart"
echo "pushed to $G"
