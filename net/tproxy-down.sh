#!/bin/sh
ip rule del fwmark 1 lookup 100 2>/dev/null || true
ip route flush table 100 2>/dev/null || true
nft delete table ip cb 2>/dev/null || true
