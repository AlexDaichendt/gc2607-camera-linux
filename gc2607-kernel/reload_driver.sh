#!/bin/bash
# Reload GC2607 driver with new settings

set -e

echo "=== Reloading GC2607 Driver ==="
echo ""

# Stop gstreamer if running
echo "Stopping gstreamer pipeline..."
pkill -f "gst-launch.*video" 2>/dev/null || true
sleep 1

# Disable media link first
echo "Disabling media link..."
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[0]' 2>/dev/null || true
sleep 1

# Unload in correct order: gc2607 can only be removed BEFORE IPU modules are reloaded
echo "Unloading all camera modules..."
sudo modprobe -r intel-ipu6-isys 2>/dev/null || true
sudo modprobe -r intel-ipu6 2>/dev/null || true
sudo rmmod gc2607 2>/dev/null || true
sleep 2

# Reload IPU modules
echo "Loading IPU6 modules..."
sudo modprobe videodev
sudo modprobe v4l2-async
sudo modprobe intel-ipu6
sudo modprobe intel-ipu6-isys
sleep 2

# Load new GC2607 driver
echo "Loading GC2607 driver with new defaults..."
sudo insmod gc2607.ko
sleep 2

# Configure format and enable link
echo "Configuring camera..."
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":0 [fmt:SGRBG10_1X10/1920x1080]'
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":1 [fmt:SGRBG10_1X10/1920x1080]'
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'

echo ""
echo "✅ Driver reloaded successfully"
echo ""
echo "Current control settings:"
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls
echo ""
echo "Note: Gain is now LUT index (0-16), not raw value"
echo "  Index 0 = 1.0x gain (lowest noise)"
echo "  Index 2 = 1.45x gain (default)"
echo "  Index 4 = 2.0x gain"
echo "  Index 8 = 4.0x gain"
echo "  Index 16 = 15.8x gain (max)"
echo ""
