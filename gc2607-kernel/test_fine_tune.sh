#!/bin/bash
# Fine-tune exposure and gain in the brightness transition zone

set -e

echo "=== Fine-Tuning Exposure/Gain (High Range) ==="
echo ""
echo "Testing very small increments around the bright range"
echo ""

./fix_format.sh > /dev/null 2>&1

# Create output directory
mkdir -p test_images_fine
cd test_images_fine

echo "Starting fine-grained tests..."
echo ""

# Focus on high exposure, very fine gain increments
# Between gain 240 (too dark) and 255 (too bright/grainy)
# Test every 3 units for very fine control
EXPOSURES=(1300 1320 1335)
GAINS=(240 243 246 249 252 255)

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

        # Convert (no brightness multiplier)
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
echo "=== Fine-Tuning Complete ==="
echo ""
echo "All images saved in: test_images_fine/"
echo ""
echo "To review:"
echo "  cd test_images_fine"
echo "  feh --info \"echo '%f'\" test_*.png"
echo ""
echo "Use 'd' key to toggle filename display"
echo "Gain increments are only 5 units apart (230, 235, 240, 245, 250, 255)"
echo "Exposure increments are ~30 units apart"
