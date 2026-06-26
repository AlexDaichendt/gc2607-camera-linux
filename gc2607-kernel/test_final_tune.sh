#!/bin/bash
# Final tuning between gain 252 and 255

set -e

echo "=== Final Tuning (gain 252-255) ==="
echo ""
echo "Testing single-unit increments"
echo ""

./fix_format.sh > /dev/null 2>&1

# Create output directory
mkdir -p test_images_final
cd test_images_final

echo "Starting final tests..."
echo ""

# Test exposure 1335 with gains 252, 253, 254, 255
EXPOSURE=1335
GAINS=(252 253 254 255)

counter=1
total=${#GAINS[@]}

for gain in "${GAINS[@]}"; do
    filename=$(printf "final_exp%04d_gain%03d.png" $EXPOSURE $gain)

    echo "[$counter/$total] Testing: exposure=$EXPOSURE, gain=$gain"

    # Set controls
    v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=$EXPOSURE,analogue_gain=$gain 2>/dev/null

    # Capture
    v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=temp.raw 2>/dev/null

    # Convert (no brightness multiplier)
    ../view_raw_bright.py temp.raw 1.0 > /dev/null 2>&1

    # Rename temp.png to our target filename
    if [ -f temp.png ]; then
        mv temp.png "$filename"
    fi

    rm -f temp.raw

    counter=$((counter + 1))
done

cd ..

echo ""
echo "=== Final Tuning Complete ==="
echo ""
echo "All images saved in: test_images_final/"
echo ""
echo "To review:"
echo "  cd test_images_final"
echo "  feh --info \"echo '%f'\" final_*.png"
echo ""
echo "Pick the gain value (252, 253, 254, or 255) that looks best!"
