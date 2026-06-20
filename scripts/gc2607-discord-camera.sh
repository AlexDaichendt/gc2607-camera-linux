#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-/dev/video60}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
FPS="${FPS:-30}"
FLIP_METHOD="${FLIP_METHOD:-rotate-180}"
PREFIX="${GC2607_PREFIX:-$HOME/opt/gc2607-ipu6}"

if [[ ! -e "$DEVICE" ]]; then
    cat >&2 <<EOF
$DEVICE does not exist.

Create the virtual Discord camera with:

  sudo modprobe v4l2loopback video_nr=${DEVICE#/dev/video} card_label="GC2607 HAL Camera" exclusive_caps=1

Then run this script again.
EOF
    exit 1
fi

if [[ ! -d "$PREFIX" ]]; then
    echo "Missing HAL prefix: $PREFIX" >&2
    exit 1
fi

export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0"
export GST_REGISTRY="$PREFIX/gstreamer-registry.bin"

exec gst-launch-1.0 -e \
    icamerasrc device-name=gc2607-uf \
    ! "video/x-raw,format=NV12,width=1920,height=1080,framerate=${FPS}/1" \
    ! queue leaky=downstream max-size-buffers=2 \
    ! videoconvert \
    ! videoflip method="$FLIP_METHOD" \
    ! videoscale \
    ! "video/x-raw,format=YUY2,width=${WIDTH},height=${HEIGHT},framerate=${FPS}/1" \
    ! v4l2sink device="$DEVICE" sync=false
