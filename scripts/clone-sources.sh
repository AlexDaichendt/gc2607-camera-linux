#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${1:-${WORKDIR:-$HOME/src/gc2607-camera}}"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

clone_if_missing() {
    local url="$1"
    local dir="$2"

    if [[ -d "$dir/.git" ]]; then
        echo "Already present: $WORKDIR/$dir"
        return
    fi

    git clone "$url" "$dir"
}

clone_if_missing https://github.com/abbood/gc2607-v4l2-driver.git gc2607-v4l2-driver
clone_if_missing https://github.com/intel/ipu6-camera-hal.git ipu6-camera-hal
clone_if_missing https://github.com/intel/ipu6-drivers.git ipu6-drivers

cat <<EOF
Source repos are ready in:
  $WORKDIR

Next:
  export WORKDIR="$WORKDIR"
  export BRINGUP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  "\$BRINGUP/scripts/apply-patches.sh" "\$WORKDIR"
EOF
