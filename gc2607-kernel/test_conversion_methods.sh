#!/bin/bash
# Test different Bayer to RGB conversion methods

set -e

echo "=== Testing Different Conversion Methods ==="
echo ""

# Set optimal values
echo "Setting optimal exposure/gain (1335/253)..."
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=253

# Capture one raw image
echo "Capturing raw image..."
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test_raw.raw 2>/dev/null

echo ""
echo "Converting with different methods..."
echo ""

# Method 1: Our simple Python script
echo "1. Our Python script (simple demosaicing)..."
./view_raw_bright.py test_raw.raw 1.0 > /dev/null 2>&1
mv test.png convert_python_simple.png
echo "   ✅ Saved: convert_python_simple.png"

# Method 2: FFmpeg rawvideo with bayer decoding
echo "2. FFmpeg (professional Bayer decoder)..."
# Convert raw to video stream that ffmpeg can process
ffmpeg -f rawvideo -pixel_format bayer_grbg10le -video_size 1920x1080 \
    -i test_raw.raw -frames:v 1 -pix_fmt rgb24 convert_ffmpeg.png -y 2>&1 | grep -E "(frame=|Output)" || echo "   Note: FFmpeg may not support this Bayer format"

if [ -f convert_ffmpeg.png ]; then
    echo "   ✅ Saved: convert_ffmpeg.png"
else
    echo "   ❌ FFmpeg failed (format not supported)"
fi

# Method 3: dcraw (if available - used for raw photo processing)
echo "3. dcraw (professional raw converter)..."
if command -v dcraw &> /dev/null; then
    # dcraw is used for digital camera raw files
    dcraw -T -4 -o 1 test_raw.raw 2>&1 | head -3 || true
    if [ -f test_raw.tiff ]; then
        convert test_raw.tiff convert_dcraw.png
        echo "   ✅ Saved: convert_dcraw.png"
    else
        echo "   ❌ dcraw failed"
    fi
else
    echo "   ⊘ dcraw not installed"
fi

# Method 4: Try different pixel format assumption
echo "4. Python with adjusted brightness..."
./view_raw_bright.py test_raw.raw 2.0 > /dev/null 2>&1
mv test.png convert_python_2x.png
echo "   ✅ Saved: convert_python_2x.png (2x brightness)"

./view_raw_bright.py test_raw.raw 0.5 > /dev/null 2>&1
mv test.png convert_python_half.png
echo "   ✅ Saved: convert_python_half.png (0.5x brightness)"

echo ""
echo "=== Comparison ==="
echo ""
ls -1 convert_*.png 2>/dev/null | while read f; do
    echo "  $f"
done

echo ""
echo "View all:"
echo "  feh convert_*.png"
echo ""
echo "Look for differences in:"
echo "  - Color accuracy (green tint?)"
echo "  - Noise/grain levels"
echo "  - Overall quality"
