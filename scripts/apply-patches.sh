#!/usr/bin/env bash
set -euo pipefail

BRINGUP="${BRINGUP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SOURCE_ROOT="${1:-${WORKDIR:-$BRINGUP/third_party}}"
DRIVER="${DRIVER:-$SOURCE_ROOT/gc2607-v4l2-driver}"
HAL="${HAL:-$SOURCE_ROOT/ipu6-camera-hal}"
IPU6_DRIVERS="${IPU6_DRIVERS:-$SOURCE_ROOT/ipu6-drivers}"

if [[ ! -d "$DRIVER/.git" ]]; then
    echo "Missing driver repo: $DRIVER" >&2
    echo "Run '$BRINGUP/scripts/clone-sources.sh' to initialize submodules, or set DRIVER=/path/to/gc2607-v4l2-driver." >&2
    exit 1
fi

if [[ ! -d "$HAL/.git" ]]; then
    echo "Missing HAL repo: $HAL" >&2
    echo "Run '$BRINGUP/scripts/clone-sources.sh' to initialize submodules, or set HAL=/path/to/ipu6-camera-hal." >&2
    exit 1
fi

if [[ ! -d "$IPU6_DRIVERS/.git" ]]; then
    echo "Missing ipu6-drivers repo: $IPU6_DRIVERS" >&2
    echo "Run '$BRINGUP/scripts/clone-sources.sh' to initialize submodules, or set IPU6_DRIVERS=/path/to/ipu6-drivers." >&2
    exit 1
fi

apply_patch_once() {
    local repo="$1"
    local patch="$2"

    cd "$repo"
    if git apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "Already applied: $patch"
        return
    fi

    git apply "$patch"
    echo "Applied: $patch"
}

apply_patch_once "$DRIVER" "$BRINGUP/patches/driver/0001-gc2607-controls-timing-for-ipu6.patch"
apply_patch_once "$HAL" "$BRINGUP/patches/hal/0001-gc2607-profile-and-psys-padding.patch"
apply_patch_once "$HAL" "$BRINGUP/patches/hal/0002-add-gc2607-sensor-xml.patch"
apply_patch_once "$IPU6_DRIVERS" "$BRINGUP/patches/ipu6-drivers/0001-cio2-bridge-add-gc2607-sensor.patch"

"$BRINGUP/scripts/install-hal-assets.sh" "$HAL"

cat <<EOF
Patches and HAL assets are applied.

Next driver install:
  sudo DRIVER="$DRIVER" "$BRINGUP/scripts/install-gc2607-dkms.sh"

IPU bridge note:
  The ipu6-drivers bridge patch only affects older kernels where this source
  tree builds the bridge. If your kernel provides ipu-bridge itself, rebuild or
  override the distro kernel module with the GC2607 entry. See:
    $BRINGUP/docs/ipu-bridge.md

Next HAL build depends on your local CMake configuration. If you already configured build-gc2607:
  cd "$HAL"
  cmake --build build-gc2607 -j"\$(nproc)"
  cmake --install build-gc2607 --prefix "\$HOME/opt/gc2607-ipu6"
EOF
