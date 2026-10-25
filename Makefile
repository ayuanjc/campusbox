# CampusBox 固件工程
SHELL := /bin/sh
ROOT  := $(CURDIR)
OUT   := $(ROOT)/build

.PHONY: help deps config build push smoke clean

help:
	@echo "make deps    检查构建依赖"
	@echo "make config  生成 mihomo 配置（读 uci，写 /etc/mihomo/config.yaml）"
	@echo "make build   用 imagebuilder 产出固件（需 IB_DIR）"
	@echo "make push    把 overlay 推到已连接的设备（需设备 IP）"
	@echo "make smoke   上机冒烟测试"

deps:
	@sh tests/check-deps.sh

config:
	@sh mihomo/gen-config.sh

build:
	@sh imagebuilder/build.sh "$(OUT)"

push:
	@sh tests/push-overlay.sh

smoke:
	@sh tests/smoke.sh

clean:
	rm -rf $(OUT)
