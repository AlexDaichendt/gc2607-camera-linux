#!/bin/bash
# Quick capture test (run after init_camera.sh)

set -e

echo "=== Quick Capture Test ==="
echo ""

# Check if camera is initialized
if [ ! -e /dev/v4l-subdev6 ]; then
    echo "Error: Camera not initialized. Run: sudo ./init_camera.sh"
    exit 1
fi

echo "Current settings:"
v4l2-ctl -d /dev/v4l-subdev6 --get-ctrl exposure,analogue_gain
echo ""

echo "Capturing image..."
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=capture.raw

echo "Converting to PNG (no brightness adjustment)..."
./view_raw_bright.py capture.raw 1.0

echo ""
echo "✅ Image saved as: test.png"
echo ""
echo "View: feh test.png"
