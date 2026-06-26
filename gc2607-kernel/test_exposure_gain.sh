#!/bin/bash
# Test exposure and gain controls to find optimal settings

set -e

echo "=== Testing GC2607 Exposure and Gain Controls ==="
echo ""

# Check if modules are loaded
if ! lsmod | grep -q gc2607; then
    echo "Error: gc2607 module not loaded"
    exit 1
fi

# Setup format and link
echo "Setting up video format and media link..."
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'

echo ""
echo "Current control values:"
v4l2-ctl -d /dev/v4l-subdev6 --get-ctrl exposure,analogue_gain
echo ""

# Test 1: Default settings
echo "=== Test 1: Default (exposure=1104, gain=128) ==="
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1104,analogue_gain=128
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test_default.raw
./view_raw_bright.py test_default.raw 1.0
mv test.png test_default.png
echo "Saved: test_default.png"
echo ""

# Test 2: Higher exposure
echo "=== Test 2: Higher exposure (exposure=1335, gain=128) ==="
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=128
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test_high_exp.raw
./view_raw_bright.py test_high_exp.raw 1.0
mv test.png test_high_exp.png
echo "Saved: test_high_exp.png"
echo ""

# Test 3: Higher gain
echo "=== Test 3: Higher gain (exposure=1104, gain=200) ==="
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1104,analogue_gain=200
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test_high_gain.raw
./view_raw_bright.py test_high_gain.raw 1.0
mv test.png test_high_gain.png
echo "Saved: test_high_gain.png"
echo ""

# Test 4: Both maxed
echo "=== Test 4: Maximum (exposure=1335, gain=255) ==="
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=255
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test_max.raw
./view_raw_bright.py test_max.raw 1.0
mv test.png test_max.png
echo "Saved: test_max.png"
echo ""

# Test 5: Low exposure
echo "=== Test 5: Low exposure (exposure=500, gain=128) ==="
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=500,analogue_gain=128
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test_low_exp.raw
./view_raw_bright.py test_low_exp.raw 1.0
mv test.png test_low_exp.png
echo "Saved: test_low_exp.png"
echo ""

echo "=== Testing Complete ==="
echo ""
echo "Generated images:"
echo "  test_default.png    - Default (exp=1104, gain=128)"
echo "  test_high_exp.png   - High exposure (exp=1335, gain=128)"
echo "  test_high_gain.png  - High gain (exp=1104, gain=200)"
echo "  test_max.png        - Maximum (exp=1335, gain=255)"
echo "  test_low_exp.png    - Low exposure (exp=500, gain=128)"
echo ""
echo "View all images: feh test_*.png"
echo "Or view individually to compare brightness"
