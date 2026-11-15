#!/bin/bash
set -euo pipefail

[[ "${WRT_CONFIG:-}" == "IPQ60XX-ER1" ]] || exit 0

add_feed() {
	local line=$1
	if ! grep -F -q "$line" feeds.conf.default; then
		printf '%s\n' "$line" >> feeds.conf.default
	fi
}

add_feed 'src-git daeuniverse https://github.com/daeuniverse/openwrt-packages.git^bb039381d2ae9a84dd0c40607c00ccf9fd9fdabf'
