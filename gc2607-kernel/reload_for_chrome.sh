#!/bin/bash
# Reload v4l2loopback with Chrome-compatible settings

set -e

echo "=== Reloading v4l2loopback for Chrome compatibility ==="
echo ""

# Kill gstreamer if running
echo "Stopping gstreamer pipeline..."
pkill -f "gst-launch.*video48" 2>/dev/null || true
sleep 1

# Unload v4l2loopback
echo "Unloading v4l2loopback..."
sudo modprobe -r v4l2loopback
sleep 1

# Reload with Chrome-friendly parameters
echo "Loading v4l2loopback with Chrome-compatible settings..."
sudo modprobe v4l2loopback \
    devices=1 \
    video_nr=50 \
    card_label="GC2607 RGB Camera" \
    exclusive_caps=1 \
    max_buffers=2

echo ""
echo "✅ v4l2loopback reloaded"
echo ""

# Find the new device (try both possible names)
VIRT_DEV=$(v4l2-ctl --list-devices | grep -A1 "GC2607 RGB" | grep "/dev/video" | tr -d '\t' | head -1)

if [ -z "$VIRT_DEV" ]; then
    # Fallback to video50 if we can't find it by name
    if [ -e /dev/video50 ]; then
        VIRT_DEV=/dev/video50
    else
        echo "❌ Error: Could not find virtual camera device"
        exit 1
    fi
fi

echo "Virtual camera: $VIRT_DEV"
echo ""

# Set optimal exposure/gain for good brightness
# Exposure: 2002 (max), Gain: 16 (max, LUT index)
echo "Setting camera parameters..."
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=2002,analogue_gain=16

# White balance gains (calculated from gray world)
R_GAIN=1.034
G_GAIN=1.000
B_GAIN=1.246

# Convert to frei0r parameters (0.5 = neutral)
R_PARAM=$(echo "scale=3; 0.5 * $R_GAIN" | bc)
G_PARAM=$(echo "scale=3; 0.5 * $G_GAIN" | bc)
B_PARAM=$(echo "scale=3; 0.5 * $B_GAIN" | bc)

echo ""
echo "Starting conversion pipeline with white balance..."
echo "WB gains: R=$R_GAIN, G=$G_GAIN, B=$B_GAIN"
echo "Press Ctrl+C to stop"
echo ""

# Start pipeline with white balance at 24fps for Chrome
gst-launch-1.0 -v \
    v4l2src device=/dev/video0 ! \
    "video/x-bayer,format=grbg10le,width=1920,height=1080,framerate=24/1" ! \
    bayer2rgb ! \
    videoflip method=rotate-180 ! \
    videoconvert ! \
    "video/x-raw,format=RGBA" ! \
    frei0r-filter-coloradj-rgb r=$R_PARAM g=$G_PARAM b=$B_PARAM keep-luma=false ! \
    videoconvert ! \
    "video/x-raw,format=I420,framerate=24/1" ! \
    v4l2sink device=$VIRT_DEV
