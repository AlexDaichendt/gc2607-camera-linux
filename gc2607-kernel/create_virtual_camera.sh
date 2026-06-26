#!/bin/bash
# Create virtual RGB camera for use with OBS/Meet/etc

set -e

echo "=== Creating Virtual RGB Camera ==="
echo ""

# Check if v4l2loopback is installed
if ! lsmod | grep -q v4l2loopback; then
    echo "Installing v4l2loopback module..."
    if ! pacman -Q v4l2loopback-dkms &>/dev/null; then
        echo "Please install: sudo pacman -S v4l2loopback-dkms"
        exit 1
    fi
    sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="GC2607 RGB" exclusive_caps=1
fi

# Find the actual v4l2loopback device
VIRT_DEV=$(v4l2-ctl --list-devices | grep -A1 "GC2607 RGB" | grep "/dev/video" | tr -d '\t')
if [ -z "$VIRT_DEV" ]; then
    echo "Error: Could not find virtual camera device"
    exit 1
fi

echo "Virtual camera device: $VIRT_DEV"
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
echo "Starting Bayer to RGB conversion pipeline with white balance..."
echo "WB gains: R=$R_GAIN, G=$G_GAIN, B=$B_GAIN"
echo "Press Ctrl+C to stop"
echo ""

# Use gstreamer to convert Bayer to RGB and feed to virtual camera
# videoflip method=rotate-180 flips the image right-side up
gst-launch-1.0 -v \
    v4l2src device=/dev/video0 ! \
    "video/x-bayer,format=grbg10le,width=1920,height=1080,framerate=30/1" ! \
    bayer2rgb ! \
    videoflip method=rotate-180 ! \
    videoconvert ! \
    "video/x-raw,format=RGBA" ! \
    frei0r-filter-coloradj-rgb r=$R_PARAM g=$G_PARAM b=$B_PARAM keep-luma=false ! \
    videoconvert ! \
    "video/x-raw,format=YUY2" ! \
    v4l2sink device=$VIRT_DEV

echo ""
echo "Pipeline stopped."
