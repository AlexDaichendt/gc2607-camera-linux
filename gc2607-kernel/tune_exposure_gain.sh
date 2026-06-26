#!/bin/bash
# Script to quickly test different exposure/gain combinations
# Usage: ./tune_exposure_gain.sh <exposure> <gain>

set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <exposure> <gain_index>"
    echo ""
    echo "Current values:"
    v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls | grep -E "(exposure|analogue_gain)"
    echo ""
    echo "Suggested starting points to try:"
    echo "  $0 800 4   # Medium exposure, moderate gain"
    echo "  $0 500 6   # Lower exposure, slightly higher gain"
    echo "  $0 1000 2  # Higher exposure, low gain (cleaner)"
    echo "  $0 400 8   # Low exposure, higher gain (more noise but better range)"
    echo ""
    echo "Tips:"
    echo "  - Lower exposure = less motion blur, need higher gain"
    echo "  - Lower gain = less noise, need more exposure"
    echo "  - Start with mid-range values and adjust"
    exit 1
fi

EXPOSURE=$1
GAIN=$2

echo "========================================="
echo "Testing: Exposure=$EXPOSURE, Gain=$GAIN"
echo "========================================="

# Set controls
echo "Setting exposure to $EXPOSURE..."
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=$EXPOSURE

echo "Setting gain to $GAIN..."
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl analogue_gain=$GAIN

# Capture image
echo "Capturing test image..."
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=tune_exp${EXPOSURE}_gain${GAIN}.raw

# Convert with white balance
echo "Converting with white balance..."
./view_raw_wb.py tune_exp${EXPOSURE}_gain${GAIN}.raw 3.0

# Rename output
mv tune_exp${EXPOSURE}_gain${GAIN}.png tune_exp${EXPOSURE}_gain${GAIN}_wb.png

echo ""
echo "========================================="
echo "✅ Test complete!"
echo "Image saved as: tune_exp${EXPOSURE}_gain${GAIN}_wb.png"
echo ""
echo "View with: feh tune_exp${EXPOSURE}_gain${GAIN}_wb.png"
echo ""
echo "Current settings:"
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls | grep -E "(exposure|analogue_gain)"
echo "========================================="
