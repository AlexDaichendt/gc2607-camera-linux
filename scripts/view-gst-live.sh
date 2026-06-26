#!/usr/bin/env bash
#
# view-gst-live.sh - live preview from the GC2607 through the IPU6 HAL
# (icamerasrc / libcamhal, 3A+ISP path). Mirrors capture-gst-frame.sh but
# renders to a window instead of writing JPEGs.
#
# Usage:
#   ./scripts/view-gst-live.sh                 # autovideosink
#   GC2607_SINK=waylandsink ./scripts/view-gst-live.sh
#   GC2607_FLIP_METHOD=none ./scripts/view-gst-live.sh
#
set -euo pipefail

PREFIX="${GC2607_PREFIX:-$HOME/opt/gc2607-ipu6}"
FLIP_METHOD="${GC2607_FLIP_METHOD:-rotate-180}"
SINK="${GC2607_SINK:-autovideosink}"

if [[ ! -d "$PREFIX" ]]; then
    echo "Missing HAL prefix: $PREFIX" >&2
    exit 1
fi

export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0${GST_PLUGIN_PATH:+:$GST_PLUGIN_PATH}"
export GST_REGISTRY="${GST_REGISTRY:-$PREFIX/gstreamer-registry.bin}"

exec gst-launch-1.0 -v \
    icamerasrc device-name=gc2607-uf \
    ! "video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1" \
    ! videoflip method="$FLIP_METHOD" \
    ! videoconvert \
    ! "$SINK" sync=false
