#!/bin/bash

apply_sed_to_matches() {
	local SEARCH_DIR=$1
	local FILE_NAME=$2
	local SED_EXPR=$3
	local MATCHES

	MATCHES=$(find "$SEARCH_DIR" -type f -name "$FILE_NAME" 2>/dev/null)
	if [ -n "$MATCHES" ]; then
		while IFS= read -r TARGET_FILE; do
			sed -i "$SED_EXPR" "$TARGET_FILE"
		done <<< "$MATCHES"
	fi
}

#移除luci-app-attendedsysupgrade
apply_sed_to_matches "./feeds/luci/collections/" "Makefile" "/attendedsysupgrade/d"

#修改默认主题
#sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#sed -i "s/luci-theme-.*$/luci-theme-bootstrap/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")

#修改immortalwrt.lan关联IP
apply_sed_to_matches "./feeds/luci/modules/luci-mod-system/" "flash.js" "s/192\\.168\\.[0-9]*\\.[0-9]*/$WRT_IP/g"
#添加编译日期标识
apply_sed_to_matches "./feeds/luci/modules/luci-mod-status/" "10_system.js" "s/(\\(luciversion || ''\\))/(\\1) + (' \\/ $WRT_MARK-$WRT_DATE')/g"

# ER1 has no radios: do not generate or modify Wi-Fi defaults.
WIFI_DEFAULTS_DIR="./package/base-files/files/etc/uci-defaults"
mkdir -p "$WIFI_DEFAULTS_DIR"


# =========================================================
# 闪存寿命与存储保护：合规初始化每周 fstrim 定时调度 (防止高频 Docker 磨损 eMMC)
# 架构归位说明：
# 1. 彻底移除开机常驻自启软链接 (/etc/rc.d/S99fstrim)，杜绝每次开机强行复活用户已删除的任务与杀进程重启 cron
# 2. 将出厂定时任务初始化归位至标准 uci-defaults 脚本 (98-default-fstrim)
#    - 构建期 (IPKG_INSTROOT)：退出 1 阻断构建阶段提前删除，随 rootfs 下发
#    - 运行期保留配置升级：检测到既有 /etc/crontabs/root 时严格静默退出 0，不破坏用户既有配置与 cron 状态
#    - 运行期全新安装/恢复出厂：仅在无既有配置时写入默认每周 trim 任务并启动 cron，执行后由系统自动销毁 (rm -f)
# 3. 提供纯净的手动执行脚本 (/etc/init.d/fstrim)，仅负责触发文件系统 trim，绝不越权篡改 crontab 或重启 cron
# =========================================================
INIT_DIR="./package/base-files/files/etc/init.d"
RCD_DIR="./package/base-files/files/etc/rc.d"
mkdir -p "$INIT_DIR" "$RCD_DIR"

FSTRIM_INIT="$INIT_DIR/fstrim"
cat << 'EOF_FSTRIM' > "$FSTRIM_INIT"
#!/bin/sh /etc/rc.common
# Weekly fstrim manual service for Athena AX6600 eMMC flash wear leveling

START=99

start() {
	TRIM_CMD="/sbin/fstrim"
	if [ -x "/sbin/fstrim" ]; then
		TRIM_CMD="/sbin/fstrim"
	elif [ -x "/usr/sbin/fstrim" ]; then
		TRIM_CMD="/usr/sbin/fstrim"
	else
		TRIM_CMD="fstrim"
	fi
	$TRIM_CMD -av 2>&1 | logger -t fstrim
}
EOF_FSTRIM
chmod +x "$FSTRIM_INIT"

# 严格确保开机常驻自启软链接 (S99fstrim) 不存在，绝不在构建期或开机时常驻自启
rm -f "$RCD_DIR/S99fstrim"

DEFAULT_FSTRIM_SCRIPT="$WIFI_DEFAULTS_DIR/98-default-fstrim"
cat << 'EOF_FSTRIM_UCI' > "$DEFAULT_FSTRIM_SCRIPT"
#!/bin/sh
# 98-default-fstrim: Athena AX6600 (JDCloud RE-CS-02) Default fstrim Cron Initialization

SYS_PREFIX="${IPKG_INSTROOT:-${SIM_ROOT:-}}"

# 1. 在 rootfs 构建期 (IPKG_INSTROOT)：
# 必须退出非 0 状态以阻断 rootfs 构建阶段提前删除 (rm -f) 本初始化脚本，确保随 rootfs 下发并在目标机首次开机时执行。
if [ -n "$IPKG_INSTROOT" ]; then
	exit 1
fi

CRON_DIR="$SYS_PREFIX/etc/crontabs"
CRON_FILE="$CRON_DIR/root"

# 2. 检查是否为保留配置升级 (sysupgrade) 或系统已存在既有定时任务配置：
# 若检测到 /etc/crontabs/root 已存在（保留配置升级场景，包括用户已自定义修改或主动删除 trim 任务，含符号链接）：
# 严格保持静默，直接退出 0，绝不篡改用户既有定时任务，绝不触发多余的 cron 杀进程重启！
# 退出 0 后由 OpenWrt 官方 uci-defaults 机制将其自动销毁 (rm -f)，后续绝不反复运行。
if [ -e "$CRON_FILE" ] || [ -L "$CRON_FILE" ]; then
	exit 0
fi

# 3. 仅在全新刷机 / 恢复出厂设置（无既有 /etc/crontabs/root）时，创建默认每周 trim 任务并启动 cron
mkdir -p "$CRON_DIR"

if [ -n "$SYS_PREFIX" ]; then
	if [ -x "$SYS_PREFIX/sbin/fstrim" ]; then
		TRIM_CMD="/sbin/fstrim"
	elif [ -x "$SYS_PREFIX/usr/sbin/fstrim" ]; then
		TRIM_CMD="/usr/sbin/fstrim"
	else
		TRIM_CMD="fstrim"
	fi
else
	if [ -x "/sbin/fstrim" ]; then
		TRIM_CMD="/sbin/fstrim"
	elif [ -x "/usr/sbin/fstrim" ]; then
		TRIM_CMD="/usr/sbin/fstrim"
	else
		TRIM_CMD="fstrim"
	fi
fi

cat << EOF > "$CRON_FILE"
0 4 * * 0 ($TRIM_CMD -av 2>&1 | logger -t fstrim)
EOF
chmod 600 "$CRON_FILE" 2>/dev/null || true

CRON_INIT="/etc/init.d/cron"
if [ -n "$SYS_PREFIX" ]; then
	CRON_INIT="$SYS_PREFIX/etc/init.d/cron"
fi
if [ -x "$CRON_INIT" ]; then
	"$CRON_INIT" enable 2>/dev/null || true
	"$CRON_INIT" restart 2>/dev/null || true
fi

exit 0
EOF_FSTRIM_UCI
chmod +x "$DEFAULT_FSTRIM_SCRIPT"

# =========================================================
# 系统升级与资产保护：预置 keep.d 白名单，防止保留配置升级时静默丢失应用级非 UCI 用户资产
# 覆盖关键资产：/etc/docker/daemon.json, /etc/adguardhome.yaml, /root/.ssh/
# =========================================================
KEEP_DIR="./package/base-files/files/lib/upgrade/keep.d"
mkdir -p "$KEEP_DIR"

CUSTOM_KEEP_FILE="$KEEP_DIR/99-ax6600-custom"
cat << 'EOF_KEEP' > "$CUSTOM_KEEP_FILE"
/etc/docker/daemon.json
/etc/adguardhome.yaml
/root/.ssh/
EOF_KEEP
chmod 644 "$CUSTOM_KEEP_FILE"

CFG_FILE="./package/base-files/files/bin/config_generate"
if [ -f "$CFG_FILE" ]; then
	#修改默认IP地址
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
	#修改默认主机名
	sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"
fi

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#私有扩展配置注入
if [ -n "$GITHUB_WORKSPACE" ] && [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	cat "$GITHUB_WORKSPACE/Config/PRIVATE.txt" >> ./.config
elif [ -f "./Config/PRIVATE.txt" ]; then
	cat "./Config/PRIVATE.txt" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		if [ -d "$DTS_PATH" ]; then
			find "$DTS_PATH" -type f ! -iname '*nowifi*' -exec sed -i 's/ipq6018.dtsi/ipq6018-nowifi.dtsi/g' {} +
			echo "qualcommax set up nowifi successfully!"
		fi
	fi
fi

# =========================================================
# 智能系统调优：优化内存水位线 (min_free_kbytes)
# =========================================================

MIN_FREE_VAL=16384
CONF_FILE="./package/base-files/files/etc/sysctl.conf"

if [ -f "$CONF_FILE" ]; then
	# 提取当前值（只匹配非注释、行首）
	CURRENT_VAL=$(sed -n 's/^vm\.min_free_kbytes=\([0-9]\+\).*/\1/p' "$CONF_FILE")

	if [ -z "$CURRENT_VAL" ]; then
		echo "" >> "$CONF_FILE"
		echo "vm.min_free_kbytes=$MIN_FREE_VAL" >> "$CONF_FILE"
		echo "Memory patch: value not found, added $MIN_FREE_VAL."
	else
		if [ "$CURRENT_VAL" -lt "$MIN_FREE_VAL" ]; then
			sed -i "s/^vm\.min_free_kbytes=.*/vm.min_free_kbytes=$MIN_FREE_VAL/" "$CONF_FILE"
			echo "Memory patch: upgraded $CURRENT_VAL -> $MIN_FREE_VAL."
		else
			echo "Memory patch: current value ($CURRENT_VAL) is sufficient, skipped."
		fi
	fi
fi
