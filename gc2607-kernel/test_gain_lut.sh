#!/bin/bash
# Test new gain lookup table implementation

set -e

echo "=== Testing Gain LUT (Lower Noise) ==="
echo ""
echo "Gain control now uses LUT indices 0-16 for optimal noise performance"
echo "Higher indices = more gain but still lower noise than before"
echo ""

# Reload driver with new gain LUT
echo "Reloading driver..."
sudo ./init_camera.sh > /dev/null 2>&1

echo ""
echo "New gain control range:"
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls | grep analogue_gain
echo ""

# Create output directory
mkdir -p test_lut
cd test_lut

echo "Testing gain LUT indices at max exposure (1335)..."
echo ""

EXPOSURE=1335
# Test all gain indices, focusing on the higher range
GAINS=(8 9 10 11 12 13 14 15 16)

counter=1
total=${#GAINS[@]}

for gain in "${GAINS[@]}"; do
    filename=$(printf "lut_exp%04d_gain%02d.png" $EXPOSURE $gain)

    echo "[$counter/$total] Testing: exposure=$EXPOSURE, gain_index=$gain"

    # Set controls
    v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=$EXPOSURE,analogue_gain=$gain 2>/dev/null

    # Capture
    v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=temp.raw 2>/dev/null

    # Convert with improved white balance
    ../view_raw_improved.py temp.raw 1.0 on > /dev/null 2>&1
    mv temp.png "$filename"

    rm -f temp.raw

    counter=$((counter + 1))
done

cd ..

echo ""
echo "=== Testing Complete ==="
echo ""
echo "Images saved in: test_lut/"
echo ""
echo "View with:"
echo "  cd test_lut"
echo "  feh lut_*.png"
echo ""
echo "The images should have:"
echo "  ✓ Similar brightness to before"
echo "  ✓ MUCH less grain/noise"
echo ""
echo "Pick the gain index that looks best!"
