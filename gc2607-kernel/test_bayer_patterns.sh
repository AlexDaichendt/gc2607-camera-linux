#!/bin/bash
# Script to test different Bayer patterns
# Usage: ./test_bayer_patterns.sh [pattern_number]
# pattern_number: 1=BGGR, 2=GBRG, 3=GRBG (current), 4=RGGB

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <pattern_number>"
    echo "  1 = SBGGR10 (BGGR pattern)"
    echo "  2 = SGBRG10 (GBRG pattern)"
    echo "  3 = SGRBG10 (GRBG pattern) - CURRENT"
    echo "  4 = SRGGB10 (RGGB pattern)"
    exit 1
fi

PATTERN=$1

case $PATTERN in
    1)
        FORMAT="SBGGR10"
        NAME="BGGR"
        ;;
    2)
        FORMAT="SGBRG10"
        NAME="GBRG"
        ;;
    3)
        FORMAT="SGRBG10"
        NAME="GRBG"
        ;;
    4)
        FORMAT="SRGGB10"
        NAME="RGGB"
        ;;
    *)
        echo "Error: Invalid pattern number. Use 1-4."
        exit 1
        ;;
esac

echo "========================================="
echo "Testing Bayer pattern: $NAME ($FORMAT)"
echo "========================================="

# Backup original file if not already backed up
if [ ! -f gc2607.c.backup ]; then
    echo "Creating backup of gc2607.c..."
    cp gc2607.c gc2607.c.backup
fi

# Replace all occurrences of MEDIA_BUS_FMT_SGRBG10_1X10 with the new format
echo "Modifying gc2607.c..."
sed -i "s/MEDIA_BUS_FMT_S[GBR]*10_1X10/MEDIA_BUS_FMT_${FORMAT}_1X10/g" gc2607.c

# Rebuild driver
echo "Rebuilding driver..."
make clean && make

# Unload entire IPU6 stack (similar to reload_driver.sh)
echo "Stopping any camera processes..."
pkill -f "gst-launch.*video" 2>/dev/null || true
pkill -f "v4l2-ctl" 2>/dev/null || true
sleep 1

echo "Disabling media link..."
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[0]' 2>/dev/null || true
sleep 1

echo "Unloading camera modules..."
sudo modprobe -r intel-ipu6-isys 2>/dev/null || true
sudo modprobe -r intel-ipu6 2>/dev/null || true
sudo rmmod gc2607 2>/dev/null || true
sleep 2

# Reload IPU6 stack
echo "Reloading IPU6 modules..."
sudo modprobe videodev
sudo modprobe v4l2-async
sudo modprobe intel-ipu6
sudo modprobe intel-ipu6-isys
sleep 2

# Load new driver with new pattern
echo "Loading driver with $NAME pattern..."
sudo insmod gc2607.ko
sleep 2

# Set up video format with media controller
echo "Configuring media controller format..."
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":0 [fmt:'${FORMAT}'_1X10/1920x1080]'
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":1 [fmt:'${FORMAT}'_1X10/1920x1080]'

echo "Configuring video format..."
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10

# Enable media link
echo "Enabling media link..."
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'

# Capture test image
echo "Capturing test image..."
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test_${NAME}.raw

# Convert to PNG
echo "Converting to PNG..."
./view_raw_bright.py test_${NAME}.raw 5.0

# Rename output (view_raw_bright.py creates test.png)
if [ -f test.png ]; then
    mv test.png test_${NAME}.png
fi

echo ""
echo "========================================="
echo "Test complete!"
echo "Image saved as: test_${NAME}.png"
echo "Raw file saved as: test_${NAME}.raw"
echo ""
echo "View the image with:"
echo "  feh test_${NAME}.png"
echo ""
echo "To restore original driver:"
echo "  cp gc2607.c.backup gc2607.c"
echo "  make clean && make"
echo "========================================="
