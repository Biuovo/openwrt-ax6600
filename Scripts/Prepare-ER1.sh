#!/bin/bash
set -euo pipefail
[[ "${WRT_CONFIG:-}" == "IPQ60XX-ER1" ]] || exit 0

# Invoked from wrt/package, after the normal feed installation.
feed=../feeds/daeuniverse
honk="$feed/honk"
test -f "$honk/Makefile"
git clone --depth=1 --branch v0.1.0-beta.6 \
  https://github.com/daeuniverse/honk.git "$honk/src"
test "$(git -C "$honk/src" rev-parse HEAD)" = 64848881b7304e250e7a25422f4f1d86a5975eca

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
