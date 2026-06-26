#!/bin/bash
# Test exposure and gain controls for proper brightness

set -e

echo "=== Testing Brightness with Exposure/Gain Controls ==="
echo ""

# Reload driver
echo "Reloading driver..."
./reload_driver.sh > /dev/null 2>&1

# Fix CSI2 formats
echo "Configuring formats..."
./fix_format.sh > /dev/null 2>&1

echo ""
echo "Current controls:"
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls | grep -E "(exposure|gain)"
echo ""

# Test with max exposure and gain
echo "=== Test: Maximum brightness (exposure=1335, gain=255) ==="
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=255
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=bright_max.raw
./view_raw_bright.py bright_max.raw 1.0
mv test.png bright_max.png
echo "✅ Saved: bright_max.png"
echo ""

# Test with recommended settings
echo "=== Test: Recommended (exposure=1200, gain=180) ==="
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1200,analogue_gain=180
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=bright_rec.raw
./view_raw_bright.py bright_rec.raw 1.0
mv test.png bright_rec.png
echo "✅ Saved: bright_rec.png"
echo ""

echo "=== Testing Complete ==="
echo ""
echo "View images:"
echo "  feh bright_max.png    - Maximum brightness"
echo "  feh bright_rec.png    - Recommended settings"
