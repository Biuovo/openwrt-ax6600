#!/bin/bash
set -euo pipefail
[[ "${WRT_CONFIG:-}" == "IPQ60XX-ER1" ]] || exit 0

# Invoked from wrt/package, after the normal feed installation.
# This build targets the user's existing 12 MiB ER1 kernel partition.
python3 - ../target/linux/qualcommax/image/ipq60xx.mk <<'PY_ER1_IMAGE'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
s = p.read_text()
pattern = r'(?ms)^define Device/jdcloud_re-cs-07\n.*?^endef$'
blocks = list(re.finditer(pattern, s))
assert len(blocks) == 1, 'ER1 device definition missing or ambiguous'
m = blocks[0]
block, count = re.subn(r'(?m)^(\s*KERNEL_SIZE\s*:=\s*)(?:6144|12288)k\s*$',
                       r'\g<1>12288k', m.group())
assert count == 1, 'Unexpected ER1 kernel size; review image layout'
p.write_text(s[:m.start()] + block + s[m.end():])
print('ER1 kernel partition: 12288 KiB (12 MiB), gzip FIT retained')
PY_ER1_IMAGE

feed=../feeds/daeuniverse
honk="$feed/honk"
test -f "$honk/Makefile"
git clone --depth=1 --branch v0.1.0-beta.6 \
  https://github.com/daeuniverse/honk.git "$honk/src"
test "$(git -C "$honk/src" rev-parse HEAD)" = 64848881b7304e250e7a25422f4f1d86a5975eca

# The IPQ60xx target adds radio packages as DEFAULT_PACKAGES after Kconfig
# merging. ER1 is wired-only, so remove those target defaults before defconfig.
python3 - <<'PY'
from pathlib import Path
import re
rules = {
    Path('../target/linux/qualcommax/Makefile'): [
        'wpad-openssl', 'kmod-ath11k', 'kmod-ath11k-ahb', 'kmod-ath11k-pci',
    ],
    Path('../target/linux/qualcommax/ipq60xx/target.mk'): [
        'ath11k-firmware-ipq6018-ddwrt', 'kmod-nss-wifi-drv',
    ],
}
for path, names in rules.items():
    text = path.read_text()
    for name in names:
        text = re.sub(r'(?<![A-Za-z0-9_-])' + re.escape(name) + r'(?![A-Za-z0-9_-])', '', text)
    path.write_text(text)
PY

# The IPQ60xx target adds Wi-Fi packages globally. Remove those defaults before
# defconfig; the RE-CS-07 device itself is wired-only.
TARGET_MK=../target/linux/qualcommax/ipq60xx/target.mk
QCOM_MK=../target/linux/qualcommax/Makefile
if [ -f "$TARGET_MK" ]; then
  sed -i -E 's/(^|[[:space:]])(ath11k-firmware-ipq6018-ddwrt|kmod-nss-wifi-drv)([[:space:]]|$)/ /g' "$TARGET_MK"
fi
if [ -f "$QCOM_MK" ]; then
  sed -i -E 's/(^|[[:space:]])(wpad-openssl|kmod-ath11k|kmod-ath11k-ahb|kmod-ath11k-pci)([[:space:]]|$)/ /g' "$QCOM_MK"
fi

# Honk's nested `cargo +nightly` must use rustup's proxy, not OpenWrt's
# staged standalone cargo (other Rust packages keep the original host setup).
python3 - "$honk/Makefile" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
a='\tsh "$(PKG_DIR)/build.sh"'
b='\tPATH="$${CARGO_HOME:-$${HOME}/.cargo}/bin:$(PATH)" sh "$(PKG_DIR)/build.sh"'
assert s.count(a)==1, 'Official Honk recipe has changed'
p.write_text(s.replace(a,b,1))
PY

# The upstream standalone Tailscale/Daed feeds are not needed here. The only
# addition to the original PURE/PLUS packages is daeuniverse Honk.
{
  echo "honk daeuniverse/honk v0.1.0-beta.6 $(git -C "$honk/src" rev-parse HEAD)"
  echo "daeuniverse(feed) daeuniverse/openwrt-packages $(git -C "$feed" rev-parse HEAD)"
} >> "$GITHUB_WORKSPACE/package-versions.txt"

# Keep required IPQ6018 kernel capabilities in the actual kernel fragment.
# Selecting nonexistent CONFIG_KERNEL_* menu options would silently do nothing.
python3 - ../target/linux/qualcommax/ipq60xx/config-default <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
s=p.read_text()
settings={k:'y' for k in ['BPF','BPF_SYSCALL','BPF_JIT','CGROUPS','CGROUP_BPF',
    'NET_SCHED','NET_CLS_ACT','NET_XGRESS','NET_NS','QCOM_80211AX_PPE','QCOM_EDMA']}
for k,v in settings.items():
    pat=rf'^(?:CONFIG_{k}=.*|# CONFIG_{k} is not set)\n?'
    s=re.sub(pat,'',s,flags=re.M)
    s+=f'CONFIG_{k}={v}\n'
p.write_text(s)
PY
