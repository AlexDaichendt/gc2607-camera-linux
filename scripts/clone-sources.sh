#!/usr/bin/env bash
set -euo pipefail

BRINGUP="${BRINGUP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

git -C "$BRINGUP" submodule update --init --recursive

cat <<EOF
Source repos are ready in:
  $BRINGUP/third_party

The GC2607 driver source is first-party under gc2607-kernel/ (not a submodule).

Next:
  export BRINGUP="$BRINGUP"
  export HAL="\$BRINGUP/third_party/ipu6-camera-hal"
  export IPU6_DRIVERS="\$BRINGUP/third_party/ipu6-drivers"
  "\$BRINGUP/scripts/apply-patches.sh"
EOF
