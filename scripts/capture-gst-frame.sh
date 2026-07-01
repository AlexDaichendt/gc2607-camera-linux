#!/usr/bin/env bash
set -euo pipefail

PREFIX="${GC2607_PREFIX:-$HOME/opt/gc2607-ipu6}"
OUT_PREFIX="${1:-/tmp/gc2607-frame}"
FRAMES="${2:-30}"
FLIP_METHOD="${GC2607_FLIP_METHOD:-rotate-180}"

# Prefix-specific GStreamer wiring, only needed for an in-tree $HOME HAL build.
# A packaged /usr install (gc2607-ipu6-camera-hal) needs none of this because
# ld.so, pkg-config, and GStreamer all auto-discover /usr; skip it when the dev
# prefix is absent and rely on the system install.
if [[ -d "$PREFIX" ]]; then
    export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
    export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0${GST_PLUGIN_PATH:+:$GST_PLUGIN_PATH}"
    export GST_REGISTRY="${GST_REGISTRY:-$PREFIX/gstreamer-registry.bin}"
fi

rm -f "${OUT_PREFIX}"-*.jpg

gst-launch-1.0 -e -q \
    icamerasrc device-name=gc2607-uf num-buffers="$FRAMES" \
    ! "video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1" \
    ! videoflip method="$FLIP_METHOD" \
    ! videoconvert \
    ! jpegenc quality=95 \
    ! multifilesink location="${OUT_PREFIX}-%02d.jpg"

ls -1 "${OUT_PREFIX}"-*.jpg
