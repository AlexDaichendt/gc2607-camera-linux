#!/bin/bash
# Find optimal exposure and gain settings

set -e

echo "=== Finding Optimal Exposure/Gain Settings ==="
echo ""

# Ensure driver is loaded and formats are set
echo "Ensuring setup..."
./fix_format.sh > /dev/null 2>&1

echo ""
echo "Testing different exposure/gain combinations..."
echo ""

# Test 1: Moderate settings
echo "Test 1: exposure=800, gain=128"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=800,analogue_gain=128
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=opt1.raw 2>/dev/null
./view_raw_bright.py opt1.raw 1.0
mv test.png opt1_exp800_gain128.png 2>/dev/null || true
echo "  ✅ opt1_exp800_gain128.png"

# Test 2: Higher exposure, moderate gain
echo "Test 2: exposure=1000, gain=128"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1000,analogue_gain=128
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=opt2.raw 2>/dev/null
./view_raw_bright.py opt2.raw 1.0
mv test.png opt2_exp1000_gain128.png 2>/dev/null || true
echo "  ✅ opt2_exp1000_gain128.png"

# Test 3: Moderate exposure, higher gain
echo "Test 3: exposure=800, gain=160"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=800,analogue_gain=160
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=opt3.raw 2>/dev/null
./view_raw_bright.py opt3.raw 1.0
mv test.png opt3_exp800_gain160.png 2>/dev/null || true
echo "  ✅ opt3_exp800_gain160.png"

# Test 4: Balanced
echo "Test 4: exposure=900, gain=140"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=900,analogue_gain=140
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=opt4.raw 2>/dev/null
./view_raw_bright.py opt4.raw 1.0
mv test.png opt4_exp900_gain140.png 2>/dev/null || true
echo "  ✅ opt4_exp900_gain140.png"

# Test 5: Default (for comparison)
echo "Test 5: exposure=1104, gain=128 (current default)"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1104,analogue_gain=128
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=opt5.raw 2>/dev/null
./view_raw_bright.py opt5.raw 1.0
mv test.png opt5_exp1104_gain128_default.png 2>/dev/null || true
echo "  ✅ opt5_exp1104_gain128_default.png"

# Test 6: Lower settings
echo "Test 6: exposure=700, gain=150"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=700,analogue_gain=150
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=opt6.raw 2>/dev/null
./view_raw_bright.py opt6.raw 1.0
mv test.png opt6_exp700_gain150.png 2>/dev/null || true
echo "  ✅ opt6_exp700_gain150.png"

echo ""
echo "=== Testing Complete ==="
echo ""
echo "View all images to compare:"
echo "  feh opt*.png"
echo ""
echo "Look for an image with good brightness without overexposure."
echo "Then we'll update the default values in the driver."
