#!/bin/bash
# Initialize GC2607 camera driver after reboot
# Run this script with sudo after booting to set up the camera

set -e

echo "=== Initializing GC2607 Camera Driver ==="
echo ""

# Load required kernel modules
echo "Loading kernel modules..."
modprobe videodev
modprobe v4l2-async
modprobe ipu_bridge
modprobe intel-ipu6
modprobe intel-ipu6-isys

# Wait for modules to initialize
sleep 1

# Load GC2607 driver
echo "Loading GC2607 driver..."
cd "$(dirname "$0")"

# Unload if already loaded
if lsmod | grep -q gc2607; then
    echo "  Driver already loaded, reloading..."
    # Disable media link first
    media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[0]' 2>/dev/null || true
    sleep 1
    # Unload IPU modules first (this will unload gc2607 too)
    modprobe -r intel-ipu6-isys 2>/dev/null || true
    modprobe -r intel-ipu6 2>/dev/null || true
    sleep 1
    # Reload IPU modules
    modprobe intel-ipu6
    modprobe intel-ipu6-isys
    sleep 1
fi

# Load gc2607 if not already loaded
if ! lsmod | grep -q gc2607; then
    insmod gc2607.ko
fi

# Wait for device initialization
sleep 2

echo "Checking driver probe..."
dmesg | tail -20 | grep -E "gc2607|GC2607" || true

# Configure CSI2 formats (this is critical!)
echo ""
echo "Configuring CSI2 receiver formats..."
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":0 [fmt:SGRBG10_1X10/1920x1080]'
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":1 [fmt:SGRBG10_1X10/1920x1080]'

# Set video device format
echo "Configuring video device format..."
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10

# Enable media link
echo "Enabling media pipeline..."
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'

echo ""
echo "✅ Camera initialized successfully!"
echo ""
echo "Default settings:"
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls | grep -E "(exposure|gain)"
echo ""
echo "Quick capture test:"
echo "  v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test.raw"
echo "  ./view_raw_bright.py test.raw 1.0"
echo "  feh test.png"
echo ""
echo "Or run: ./test_new_defaults.sh"
