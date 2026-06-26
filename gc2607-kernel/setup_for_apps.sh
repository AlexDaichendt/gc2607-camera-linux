#!/bin/bash
# Setup camera for use with applications like OBS Studio

set -e

echo "=== Setting Up Camera for Applications ==="
echo ""

# Ensure camera is initialized
if [ ! -e /dev/v4l-subdev6 ]; then
    echo "Camera not initialized. Running init_camera.sh..."
    sudo ./init_camera.sh
fi

echo ""
echo "Setting optimal exposure/gain..."
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=253

echo ""
echo "✅ Camera ready at /dev/video0"
echo ""
echo "Camera info:"
v4l2-ctl -d /dev/video0 --info
echo ""
echo "Current format:"
v4l2-ctl -d /dev/video0 --get-fmt-video
echo ""

echo "=== How to Use ==="
echo ""
echo "1. OBS Studio:"
echo "   - Add Source → Video Capture Device (V4L2)"
echo "   - Device: /dev/video0"
echo "   - Format: BA10 or let it auto-detect"
echo "   - Resolution: 1920x1080"
echo ""
echo "2. Test with ffplay:"
echo "   ffplay -f v4l2 -pixel_format bayer_grbg10le -video_size 1920x1080 /dev/video0"
echo ""
echo "3. Test with gstreamer:"
echo "   gst-launch-1.0 v4l2src device=/dev/video0 ! 'video/x-bayer,format=grbg10le,width=1920,height=1080' ! bayer2rgb ! videoconvert ! autovideosink"
echo ""
echo "4. Adjust exposure/gain live:"
echo "   v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1200"
echo "   v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl analogue_gain=240"
echo ""
echo "NOTE: Most apps expect RGB/YUV formats, not raw Bayer."
echo "You may need a converter like v4l2loopback."
