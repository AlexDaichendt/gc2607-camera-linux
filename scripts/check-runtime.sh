#!/usr/bin/env bash
set -euo pipefail

PREFIX="${GC2607_PREFIX:-$HOME/opt/gc2607-ipu6}"

export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0${GST_PLUGIN_PATH:+:$GST_PLUGIN_PATH}"
export GST_REGISTRY="${GST_REGISTRY:-$PREFIX/gstreamer-registry.bin}"

for command in gst-launch-1.0 gst-inspect-1.0 v4l2-ctl media-ctl modinfo dkms systemd-run; do
    printf "%-18s" "$command:"
    command -v "$command" || true
done

echo "--- gstreamer elements ---"
for element in icamerasrc videoflip videoconvert videoscale videorate jpegenc multifilesink fakesink v4l2sink; do
    if gst-inspect-1.0 "$element" >/dev/null 2>&1; then
        echo "$element: ok"
    else
        echo "$element: missing"
    fi
done

echo "--- GC2607 sensor driver ---"
dkms status -m gc2607 2>/dev/null || true
modinfo gc2607 >/dev/null 2>&1 && echo "gc2607: modinfo ok" || echo "gc2607: missing from module tree"
lsmod | rg "^gc2607\b" || echo "gc2607: not loaded"
if [[ -d /sys/bus/i2c/drivers/gc2607 ]]; then
    find /sys/bus/i2c/drivers/gc2607 -maxdepth 1 -mindepth 1 -printf "%f\n" 2>/dev/null | sort
else
    echo "/sys/bus/i2c/drivers/gc2607: missing"
fi

echo "--- IPU6 modules and PSYS ---"
dkms status -m ipu6-drivers 2>/dev/null || true
lsmod | rg "intel_ipu6|intel-ipu6" || true
[[ -e /dev/ipu-psys0 ]] && ls -l /dev/ipu-psys0 || echo "/dev/ipu-psys0: absent"

echo "--- HAL assets ---"
if [[ -d "$PREFIX" ]]; then
    find "$PREFIX/etc/camera" -iname "*gc2607*" -o -iname "graph_settings_gc2607*" 2>/dev/null | sort
else
    echo "HAL prefix missing: $PREFIX"
fi

echo "--- video devices ---"
v4l2-ctl --list-devices 2>/dev/null || true

echo "--- virtual camera ---"
modinfo v4l2loopback >/dev/null 2>&1 && echo "v4l2loopback: modinfo ok" || echo "v4l2loopback: missing from module tree"
lsmod | rg "^v4l2loopback\b" || echo "v4l2loopback: not loaded"
"$(dirname "$0")/virtual-camera.sh" status 2>/dev/null || true
