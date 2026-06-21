#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${1:-${WORKDIR:-$HOME/src/gc2607-camera}}"
BRINGUP="${BRINGUP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DRIVER="${DRIVER:-$WORKDIR/gc2607-v4l2-driver}"
HAL="${HAL:-$WORKDIR/ipu6-camera-hal}"

if [[ ! -d "$DRIVER/.git" ]]; then
    echo "Missing driver repo: $DRIVER" >&2
    exit 1
fi

if [[ ! -d "$HAL/.git" ]]; then
    echo "Missing HAL repo: $HAL" >&2
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

"$BRINGUP/scripts/install-hal-assets.sh" "$HAL"

cat <<EOF
Patches and HAL assets are applied.

Next driver install:
  sudo DRIVER="$DRIVER" "$BRINGUP/scripts/install-gc2607-dkms.sh"

Next HAL build depends on your local CMake configuration. If you already configured build-gc2607:
  cd "$HAL"
  cmake --build build-gc2607 -j"\$(nproc)"
  cmake --install build-gc2607 --prefix "\$HOME/opt/gc2607-ipu6"
EOF
