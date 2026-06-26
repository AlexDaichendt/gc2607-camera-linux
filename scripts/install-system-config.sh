#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${KERNEL:-$(uname -r)}"

have_psys_module()
{
    modinfo -k "$KERNEL" intel-ipu6-psys >/dev/null 2>&1 ||
        modinfo -k "$KERNEL" intel_ipu6_psys >/dev/null 2>&1
}

sudo install -D -m 0644 \
    "$ROOT/config/modules-load.d/intel-ipu6-psys.conf" \
    /etc/modules-load.d/intel-ipu6-psys.conf

# The gc2607 sensor module is autoloaded from its ACPI modalias (HID GCTI2607)
# once installed and depmod'd, so it needs no modules-load.d force-load entry.

sudo install -D -m 0644 \
    "$ROOT/config/udev/rules.d/70-ipu6-psys.rules" \
    /etc/udev/rules.d/70-ipu6-psys.rules

if ! have_psys_module; then
    cat >&2 <<EOF
Missing PSYS module for kernel $KERNEL.

Install it first:
  "$ROOT/scripts/install-ipu6-psys-dkms.sh"
EOF
    exit 1
fi

sudo depmod -a "$KERNEL"
sudo udevadm control --reload-rules

sudo modprobe intel-ipu6-psys 2>/dev/null ||
    sudo modprobe intel_ipu6_psys 2>/dev/null
sudo modprobe gc2607 || true

if [[ -e /dev/ipu-psys0 ]]; then
    sudo chgrp video /dev/ipu-psys0 || true
    sudo chmod 660 /dev/ipu-psys0 || true
fi

cat <<EOF
Installed system camera configuration.

Expected persistent boot pieces:
  gc2607 sensor module loaded and bound to GCTI2607
  Intel IPU6 PSYS module loaded
  /dev/ipu-psys0 owned by group video
EOF
