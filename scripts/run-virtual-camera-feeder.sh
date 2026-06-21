#!/usr/bin/env bash
set -euo pipefail

PREFIX="${GC2607_PREFIX:-$HOME/opt/gc2607-ipu6}"
DEVICE="${GC2607_VCAM_DEVICE:-/dev/video${GC2607_VCAM_VIDEO_NR:-60}}"

SOURCE_WIDTH="${GC2607_VCAM_SOURCE_WIDTH:-1920}"
SOURCE_HEIGHT="${GC2607_VCAM_SOURCE_HEIGHT:-1080}"
OUTPUT_WIDTH="${GC2607_VCAM_WIDTH:-1280}"
OUTPUT_HEIGHT="${GC2607_VCAM_HEIGHT:-720}"
FRAMERATE="${GC2607_VCAM_FRAMERATE:-30/1}"
FORMAT="${GC2607_VCAM_FORMAT:-YUY2}"
FLIP_METHOD="${GC2607_FLIP_METHOD:-rotate-180}"

if [[ ! -d "$PREFIX" ]]; then
    echo "Missing HAL prefix: $PREFIX" >&2
    exit 1
fi

if [[ ! -e "$DEVICE" ]]; then
    echo "Missing virtual camera device: $DEVICE" >&2
    echo "Create it first with scripts/virtual-camera.sh prepare." >&2
    exit 1
fi

if [[ ! -w "$DEVICE" ]]; then
    echo "Virtual camera device is not writable by this user: $DEVICE" >&2
    echo "Check v4l2loopback device permissions and video-group membership." >&2
    exit 1
fi

export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0${GST_PLUGIN_PATH:+:$GST_PLUGIN_PATH}"
export GST_REGISTRY="${GST_REGISTRY:-$PREFIX/gstreamer-registry.bin}"

exec gst-launch-1.0 -e \
    icamerasrc device-name=gc2607-uf \
    ! "video/x-raw,format=NV12,width=${SOURCE_WIDTH},height=${SOURCE_HEIGHT},framerate=${FRAMERATE}" \
    ! videoflip method="$FLIP_METHOD" \
    ! videoconvert \
    ! videoscale \
    ! videorate \
    ! "video/x-raw,format=${FORMAT},width=${OUTPUT_WIDTH},height=${OUTPUT_HEIGHT},framerate=${FRAMERATE}" \
    ! identity drop-allocation=true \
    ! v4l2sink device="$DEVICE" sync=false
