#!/bin/bash
# Comprehensive exposure and gain testing

set -e

echo "=== Comprehensive Exposure/Gain Testing ==="
echo ""
echo "This will capture images with various exposure and gain combinations."
echo "Take your time reviewing each one."
echo ""

./fix_format.sh > /dev/null 2>&1

# Create output directory
mkdir -p test_images
cd test_images

echo "Starting tests... (this will take a few minutes)"
echo ""

# Test matrix: exposure values crossed with gain values
# Higher values for dark room conditions, finer increments
EXPOSURES=(1100 1150 1200 1250 1300 1335)
GAINS=(180 195 210 225 240 255)

counter=1
total=$((${#EXPOSURES[@]} * ${#GAINS[@]}))

for exp in "${EXPOSURES[@]}"; do
    for gain in "${GAINS[@]}"; do
        filename=$(printf "test_%02d_exp%04d_gain%03d.png" $counter $exp $gain)

        echo "[$counter/$total] Testing: exposure=$exp, gain=$gain"

        # Set controls
        v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=$exp,analogue_gain=$gain 2>/dev/null

        # Capture
        v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=temp.raw 2>/dev/null

        # Convert (no brightness multiplier - we want to see native brightness)
        ../view_raw_bright.py temp.raw 1.0 > /dev/null 2>&1

        # Rename temp.png to our target filename
        if [ -f temp.png ]; then
            mv temp.png "$filename"
        fi

        rm -f temp.raw

        counter=$((counter + 1))
    done
    echo ""
done

cd ..

echo ""
echo "=== Testing Complete ==="
echo ""
echo "All images saved in: test_images/"
echo ""
echo "To review images:"
echo "  cd test_images"
echo "  feh test_*.png"
echo ""
echo "Use arrow keys to navigate through images."
echo "Filenames show exposure and gain values."
echo ""
echo "Look for an image that has:"
echo "  - Good brightness (not too dark, not washed out)"
echo "  - Low noise/grain"
echo "  - Proper colors (check green tint)"
