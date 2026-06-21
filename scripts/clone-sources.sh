#!/usr/bin/env bash
set -euo pipefail

BRINGUP="${BRINGUP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

git -C "$BRINGUP" submodule update --init --recursive

cat <<EOF
Source repos are ready in:
  $BRINGUP/third_party

Next:
  export BRINGUP="$BRINGUP"
  export DRIVER="\$BRINGUP/third_party/gc2607-v4l2-driver"
  export HAL="\$BRINGUP/third_party/ipu6-camera-hal"
  export IPU6_DRIVERS="\$BRINGUP/third_party/ipu6-drivers"
  "\$BRINGUP/scripts/apply-patches.sh"
EOF
