#!/bin/bash
# Test capture with proper ISP/conversion tools

set -e

echo "=== Testing Proper Image Conversion ==="
echo ""

# Set optimal values
echo "Setting optimal exposure/gain (1335/253)..."
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=253

echo ""
echo "=== Method 1: FFmpeg with Bayer conversion ==="
echo "Capturing with ffmpeg..."

# FFmpeg can decode Bayer formats and apply proper demosaicing
ffmpeg -f v4l2 -video_size 1920x1080 -pixel_format bayer_grbg10le \
    -i /dev/video0 -frames:v 1 -pix_fmt rgb24 capture_ffmpeg.png -y 2>&1 | grep -E "(frame|Output)"

if [ -f capture_ffmpeg.png ]; then
    echo "✅ FFmpeg capture saved: capture_ffmpeg.png"
else
    echo "❌ FFmpeg capture failed"
fi

echo ""
echo "=== Method 2: GStreamer with Bayer conversion ==="
echo "Capturing with gstreamer..."

# GStreamer pipeline with bayer2rgb plugin
gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=1 ! \
    "video/x-bayer,format=grbg10le,width=1920,height=1080" ! \
    bayer2rgb ! videoconvert ! pngenc ! \
    filesink location=capture_gstreamer.png 2>&1 | head -5 || echo "Note: gstreamer attempt completed"

if [ -f capture_gstreamer.png ]; then
    echo "✅ GStreamer capture saved: capture_gstreamer.png"
else
    echo "❌ GStreamer capture failed (may need gst-plugins-bad)"
fi

echo ""
echo "=== Method 3: Raw + ImageMagick conversion ==="
echo "Capturing raw and converting with ImageMagick..."

v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=capture_test.raw 2>/dev/null

# Try ImageMagick if available
if command -v convert &> /dev/null; then
    # Convert raw Bayer to RGB (ImageMagick might have better demosaicing)
    ./view_raw_bright.py capture_test.raw 1.0 > /dev/null 2>&1
    mv test.png capture_python.png
    echo "✅ Python conversion saved: capture_python.png"
else
    echo "❌ ImageMagick not available"
fi

echo ""
echo "=== Comparison ==="
echo ""
echo "View the captures:"
echo "  feh capture_ffmpeg.png capture_gstreamer.png capture_python.png"
echo ""
echo "Compare:"
echo "  - capture_ffmpeg.png    (FFmpeg Bayer decoder)"
echo "  - capture_gstreamer.png (GStreamer bayer2rgb)"
echo "  - capture_python.png    (Our simple Python script)"
echo ""
echo "Check which one has:"
echo "  ✓ Less/no green tint"
echo "  ✓ Better colors"
echo "  ✓ Less grain"
