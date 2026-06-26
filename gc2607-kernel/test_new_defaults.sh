#!/bin/bash
# Test new default exposure and gain values

set -e

echo "=== Testing New Default Values ==="
echo ""

# Reload driver
echo "Reloading driver with new defaults..."
./reload_driver.sh > /dev/null 2>&1

# Fix CSI2 formats
./fix_format.sh > /dev/null 2>&1

echo ""
echo "Default control values (should be exposure=1300, gain=220):"
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls | grep -E "(exposure|gain)"
echo ""

echo "Capturing image with default settings..."
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=default_test.raw 2>/dev/null
./view_raw_bright.py default_test.raw 1.0
mv test.png default_test.png 2>/dev/null || true

echo ""
echo "✅ Image captured with new defaults!"
echo ""
echo "View: feh default_test.png"
echo ""
echo "If this looks good, Phase 7 is complete! 🎉"
