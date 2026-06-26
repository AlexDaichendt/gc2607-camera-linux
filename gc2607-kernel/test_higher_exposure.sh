#!/bin/bash
# Test higher exposure and gain settings

set -e

echo "=== Testing Higher Exposure/Gain Settings ==="
echo ""

./fix_format.sh > /dev/null 2>&1

echo "Testing higher combinations..."
echo ""

# Test 1: Higher exposure, moderate gain
echo "Test 1: exposure=1100, gain=180"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1100,analogue_gain=180
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=high1.raw 2>/dev/null
./view_raw_bright.py high1.raw 1.0
mv test.png high1_exp1100_gain180.png 2>/dev/null || true
echo "  ✅ high1_exp1100_gain180.png"

# Test 2: High exposure, high gain
echo "Test 2: exposure=1200, gain=200"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1200,analogue_gain=200
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=high2.raw 2>/dev/null
./view_raw_bright.py high2.raw 1.0
mv test.png high2_exp1200_gain200.png 2>/dev/null || true
echo "  ✅ high2_exp1200_gain200.png"

# Test 3: Very high exposure, moderate gain
echo "Test 3: exposure=1250, gain=180"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1250,analogue_gain=180
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=high3.raw 2>/dev/null
./view_raw_bright.py high3.raw 1.0
mv test.png high3_exp1250_gain180.png 2>/dev/null || true
echo "  ✅ high3_exp1250_gain180.png"

# Test 4: Moderate exposure, very high gain
echo "Test 4: exposure=1000, gain=220"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1000,analogue_gain=220
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=high4.raw 2>/dev/null
./view_raw_bright.py high4.raw 1.0
mv test.png high4_exp1000_gain220.png 2>/dev/null || true
echo "  ✅ high4_exp1000_gain220.png"

# Test 5: Very high both
echo "Test 5: exposure=1300, gain=220"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1300,analogue_gain=220
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=high5.raw 2>/dev/null
./view_raw_bright.py high5.raw 1.0
mv test.png high5_exp1300_gain220.png 2>/dev/null || true
echo "  ✅ high5_exp1300_gain220.png"

# Test 6: Max exposure, high gain
echo "Test 6: exposure=1335, gain=210"
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=210
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=high6.raw 2>/dev/null
./view_raw_bright.py high6.raw 1.0
mv test.png high6_exp1335_gain210.png 2>/dev/null || true
echo "  ✅ high6_exp1335_gain210.png"

echo ""
echo "=== Testing Complete ==="
echo ""
echo "View all images:"
echo "  feh high*.png"
echo ""
echo "Find the one with the best balance - bright but not overexposed."
