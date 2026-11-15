#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Regression Test: Verify CI intent-aware dynamic assertion logic for PLUS plugins
# Ensures official releases guard against silent drops while allowing fork customization.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW_FILE="$REPO_ROOT/.github/workflows/WRT-CORE.yml"

BASH_BIN="${BASH:-}"
if [ -z "$BASH_BIN" ] || ! "$BASH_BIN" -c "true" 2>/dev/null; then
    if command -v bash >/dev/null 2>&1 && bash -c "true" 2>/dev/null; then
        BASH_BIN="bash"
    elif [ -x "/bin/bash" ]; then
        BASH_BIN="/bin/bash"
    elif [ -x "/usr/bin/bash" ]; then
        BASH_BIN="/usr/bin/bash"
    elif [ -x "C:/Program Files/Git/bin/bash.exe" ]; then
        BASH_BIN="C:/Program Files/Git/bin/bash.exe"
    else
        BASH_BIN="sh"
    fi
fi

echo "=== Running CI Intent-Aware Dynamic Assertion Regression Test ==="

if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "ERROR: Workflow file not found at $WORKFLOW_FILE" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'ci_assert_test')"
trap 'rm -rf "$TMP_DIR"' EXIT

# Extract the single-image ER1 assertion block from WRT-CORE.yml.
ASSERT_SNIPPET="$(awk '/# 4\. 检查 PPE 硬件流表/{flag=1} flag && /rm -f \.config.seed/{flag=0} flag' "$WORKFLOW_FILE")"
if [ -z "$ASSERT_SNIPPET" ]; then
    echo "FAIL: Failed to extract ER1 assertion block from $WORKFLOW_FILE!" >&2
    exit 1
fi

TEST_SCRIPT="$TMP_DIR/run_assert.sh"
cat << 'EOF' > "$TEST_SCRIPT"
#!/usr/bin/env bash
set -e
CONFIG_FILE="$1"
FAIL=0

cd "$(dirname "$CONFIG_FILE")"
EOF

echo "$ASSERT_SNIPPET" >> "$TEST_SCRIPT"

cat << 'EOF' >> "$TEST_SCRIPT"
if [[ $FAIL -ne 0 ]]; then
    exit 1
fi
exit 0
EOF
chmod +x "$TEST_SCRIPT"

run_case() {
    local name="$1"; local config="$2"; local expected="$3"
    printf '%s\n' "$config" > "$TMP_DIR/.config"
    set +e
    "$BASH_BIN" "$TEST_SCRIPT" "$TMP_DIR/.config" > "$TMP_DIR/output.log" 2>&1
    local actual=$?
    set -e
    if [ "$actual" -ne "$expected" ]; then
        echo "FAIL: $name expected $expected, got $actual" >&2
        cat "$TMP_DIR/output.log" >&2
        exit 1
    fi
    echo "PASS: $name"
}

run_case "valid ER1 PPE/Honk config" "CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_firewall4=y
CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-cs-07=y
CONFIG_PACKAGE_honk=y
CONFIG_PACKAGE_luci-app-honk=y
CONFIG_PACKAGE_vmlinux-btf-builtin=y
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_luci-app-adguardhome=y
CONFIG_PACKAGE_luci-app-wolultra=y" 0
run_case "missing ER1 target" "CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_honk=y
CONFIG_PACKAGE_luci-app-honk=y
CONFIG_PACKAGE_vmlinux-btf-builtin=y
CONFIG_KERNEL_DEBUG_INFO_BTF=y" 1

# -----------------------------------------------------------------------------
# 13. Actions 工作流权限收缩至最小权限验证 (杜绝 write-all 高危权限)
# -----------------------------------------------------------------------------
echo "--- Case: Verify Actions workflow permissions minimization ---"
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"
if grep -rn "permissions:[[:space:]]*write-all" "$WORKFLOW_DIR"; then
    echo "FAIL: Found leftover 'permissions: write-all' in workflows!" >&2
    exit 1
fi

for WF in "$WORKFLOW_DIR"/*.yml; do
    if ! grep -q "permissions:" "$WF"; then
        echo "FAIL: Workflow $WF missing explicit 'permissions:' specification!" >&2
        exit 1
    fi
done
echo "PASS: All Actions workflows strictly minimized (0 instances of write-all)."

echo "================================================================================"
echo "=== All Intent-Aware Dynamic Assertion & Security Regression Tests Passed! ==="
echo "================================================================================"
