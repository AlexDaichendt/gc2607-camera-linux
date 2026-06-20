#!/usr/bin/env bash
set -euo pipefail

for command in gst-launch-1.0 gst-inspect-1.0 v4l2-ctl modinfo; do
    printf "%-18s" "$command:"
    command -v "$command" || true
done

echo "--- gstreamer elements ---"
for element in icamerasrc videoconvert videoscale videoflip v4l2sink; do
    if gst-inspect-1.0 "$element" >/dev/null 2>&1; then
        echo "$element: ok"
    else
        echo "$element: missing"
    fi
done

echo "--- v4l2loopback ---"
modinfo v4l2loopback >/dev/null 2>&1 && echo "v4l2loopback: ok" || echo "v4l2loopback: missing"

echo "--- video devices ---"
v4l2-ctl --list-devices 2>/dev/null || true
