#!/usr/bin/env bash
set -euo pipefail

PREFIX="${GC2607_PREFIX:-$HOME/opt/gc2607-ipu6}"
FRAMES="${FRAMES:-120}"

if [[ ! -d "$PREFIX" ]]; then
    echo "Missing HAL prefix: $PREFIX" >&2
    exit 1
fi

export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0"
export GST_REGISTRY="$PREFIX/gstreamer-registry.bin"

exec timeout 20s gst-launch-1.0 -e -q \
    icamerasrc device-name=gc2607-uf num-buffers="$FRAMES" \
    ! "video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1" \
    ! fakesink sync=false
