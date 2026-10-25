#!/bin/sh
for t in sh git curl nft ip; do
  printf '%-8s' "$t"; command -v $t >/dev/null && echo ok || echo MISSING
done
echo "imagebuilder: 需手动设置 IB_DIR（见 imagebuilder/build.sh）"
