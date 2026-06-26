#!/bin/bash
# Final test with hybrid gain and improved white balance

set -e

echo "=== Final Test: Hybrid Gain + White Balance ==="
echo ""

# Reload driver
echo "Reloading driver..."
sudo ./init_camera.sh > /dev/null 2>&1

echo ""
echo "Current settings:"
v4l2-ctl -d /dev/v4l-subdev6 --get-ctrl exposure,analogue_gain

echo ""
echo "Capturing with optimal settings (exposure=1335, gain=253)..."
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=253
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=final.raw 2>/dev/null

echo "Converting with improved white balance..."
./view_raw_improved.py final.raw 1.0 on > /dev/null 2>&1
mv final.png final_result.png

echo ""
echo "✅ Image saved: final_result.png"
echo ""
echo "View: feh final_result.png"
echo ""
echo "This should have:"
echo "  ✓ Good brightness (like before)"
echo "  ✓ No green tint (white balance fixed)"
echo "  ✓ Acceptable grain (high gain is inherently noisy in dark rooms)"
