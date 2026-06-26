#!/bin/bash
# Create virtual RGB camera with WHITE BALANCE for OBS/Meet/etc

set -e

echo "=== Creating Virtual RGB Camera with White Balance ==="
echo ""

# Parse command line arguments for white balance gains
R_GAIN=${1:-1.2}  # Default red gain
G_GAIN=${2:-1.0}  # Default green gain (reference)
B_GAIN=${3:-1.5}  # Default blue gain

echo "White balance gains: R=$R_GAIN, G=$G_GAIN, B=$B_GAIN"
echo "(Usage: $0 [r_gain] [g_gain] [b_gain])"
echo ""

# Check if v4l2loopback is installed
if ! lsmod | grep -q v4l2loopback; then
    echo "Installing v4l2loopback module..."
    if ! pacman -Q v4l2loopback-dkms &>/dev/null; then
        echo "Please install: sudo pacman -S v4l2loopback-dkms"
        exit 1
    fi
    sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="GC2607 RGB WB" exclusive_caps=1
fi

# Find the actual v4l2loopback device
VIRT_DEV=$(v4l2-ctl --list-devices | grep -A1 "GC2607 RGB" | grep "/dev/video" | head -1 | tr -d '\t')
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

echo ""
echo "Starting Bayer to RGB conversion pipeline with WHITE BALANCE..."
echo "Press Ctrl+C to stop"
echo ""
echo "Adjust white balance by restarting with different gains:"
echo "  $0 1.0 1.0 1.3  # Reduce red, increase blue"
echo "  $0 1.5 1.0 1.2  # Increase red, increase blue"
echo ""

# GStreamer pipeline with white balance using frei0r coloradj_RGB
# frei0r r/g/b parameters: 0.0-1.0, where 0.5 is neutral (1.0x gain)
# Convert our gains to frei0r parameters: param = 0.5 * gain
R_PARAM=$(echo "scale=3; 0.5 * $R_GAIN" | bc)
G_PARAM=$(echo "scale=3; 0.5 * $G_GAIN" | bc)
B_PARAM=$(echo "scale=3; 0.5 * $B_GAIN" | bc)

echo "Frei0r RGB parameters: r=$R_PARAM, g=$G_PARAM, b=$B_PARAM"
echo ""

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
