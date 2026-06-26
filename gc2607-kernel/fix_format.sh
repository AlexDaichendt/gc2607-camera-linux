#!/bin/bash
# Fix format mismatch on CSI2 receiver

set -e

echo "=== Fixing CSI2 Format Mismatch ==="
echo ""

echo "Current CSI2 pad0 (sink) format:"
v4l2-ctl -d /dev/v4l-subdev0 --get-subdev-fmt pad=0
echo ""

echo "Setting CSI2 pad0 to 1920x1080 SGRBG10..."
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":0 [fmt:SGRBG10_1X10/1920x1080]'
echo ""

echo "Setting CSI2 pad1 to 1920x1080 SGRBG10..."
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":1 [fmt:SGRBG10_1X10/1920x1080]'
echo ""

echo "Verifying CSI2 formats:"
v4l2-ctl -d /dev/v4l-subdev0 --get-subdev-fmt pad=0
v4l2-ctl -d /dev/v4l-subdev0 --get-subdev-fmt pad=1
echo ""

echo "Setting video0 format..."
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
echo ""

echo "Enabling media link..."
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'
echo ""

echo "✅ Formats configured! Now try capturing:"
echo "   v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test.raw"
