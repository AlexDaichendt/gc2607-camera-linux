#!/bin/bash
# Simple capture test without changing controls

set -e

echo "=== Simple Capture Test ==="
echo ""

# Setup format and link
echo "Setting up video format and media link..."
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'

echo ""
echo "Current controls:"
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls
echo ""

echo "Attempting capture with default controls..."
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=simple_test.raw

if [ -s simple_test.raw ]; then
    echo "✅ Capture successful!"
    ls -lh simple_test.raw
    echo ""
    echo "Converting to PNG..."
    ./view_raw_bright.py simple_test.raw 1.0
    mv test.png simple_test.png
    echo "Saved: simple_test.png"
else
    echo "❌ Capture failed - file is empty"
    exit 1
fi
