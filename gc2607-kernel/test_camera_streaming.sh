#!/bin/bash
# Camera Streaming Test - Check if GC2607 works with IPU6

echo "==========================================="
echo "GC2607 Camera Streaming Test"
echo "==========================================="
echo ""

echo "Step 1: Checking IPU6 driver status..."
echo "---------------------------------------"
IPU6_LOADED=$(lsmod | grep -E "intel_ipu6|ipu6")
if [ -n "$IPU6_LOADED" ]; then
    echo "✅ IPU6 driver loaded:"
    lsmod | grep -E "intel_ipu6|ipu6"
else
    echo "⚠️  IPU6 driver not loaded"
    echo "   Attempting to load IPU6 modules..."
    sudo modprobe intel_ipu6_isys 2>/dev/null || echo "   Failed to load intel_ipu6_isys"
    sudo modprobe intel_ipu6_psys 2>/dev/null || echo "   Failed to load intel_ipu6_psys"
fi
echo ""

echo "Step 2: Loading GC2607 driver..."
echo "---------------------------------------"
sudo rmmod gc2607 2>/dev/null
if sudo insmod gc2607.ko; then
    echo "✅ GC2607 driver loaded"
    sleep 2
    sudo dmesg | tail -20 | grep gc2607
else
    echo "❌ Failed to load GC2607 driver"
    exit 1
fi
echo ""

echo "Step 3: Checking media devices..."
echo "---------------------------------------"
if ls /dev/media* 2>/dev/null; then
    echo "✅ Media devices found:"
    ls -l /dev/media*
else
    echo "❌ No media devices found"
    echo "   IPU6 driver might not be working"
fi
echo ""

echo "Step 4: Checking video devices..."
echo "---------------------------------------"
if ls /dev/video* 2>/dev/null; then
    echo "✅ Video devices found:"
    ls -l /dev/video*
else
    echo "⚠️  No video devices found yet"
fi
echo ""

echo "Step 5: Checking V4L2 subdevices..."
echo "---------------------------------------"
if command -v v4l2-ctl &> /dev/null; then
    echo "Running v4l2-ctl --list-subdevs:"
    v4l2-ctl --list-subdevs
    echo ""
    echo "Checking for GC2607:"
    v4l2-ctl --list-subdevs | grep -i gc2607 || echo "⚠️  GC2607 not found in subdev list"
else
    echo "⚠️  v4l2-ctl not installed"
    echo "   Install with: sudo pacman -S v4l-utils"
fi
echo ""

echo "Step 6: Media controller topology..."
echo "---------------------------------------"
if command -v media-ctl &> /dev/null; then
    echo "Scanning media devices:"
    for media in /dev/media*; do
        echo ""
        echo "=== $media ==="
        media-ctl -d $media --print-topology 2>/dev/null || echo "Failed to read topology"
    done
    echo ""
    echo "Looking for GC2607 in topology:"
    media-ctl --print-topology 2>/dev/null | grep -A 5 -i gc2607 || echo "⚠️  GC2607 not in media topology"
else
    echo "⚠️  media-ctl not installed"
    echo "   Install with: sudo pacman -S v4l-utils"
fi
echo ""

echo "Step 7: Checking kernel logs for binding..."
echo "---------------------------------------"
echo "Recent GC2607 messages:"
sudo dmesg | grep gc2607 | tail -30
echo ""
echo "Looking for async registration:"
sudo dmesg | grep -i "async.*gc2607\|gc2607.*async\|gc2607.*bound\|gc2607.*register" | tail -10
echo ""

echo "Step 8: Checking ACPI device status..."
echo "---------------------------------------"
echo "GC2607 ACPI device:"
cat /sys/bus/acpi/devices/GCTI2607*/status 2>/dev/null || echo "ACPI device not found"
echo ""
echo "I2C device:"
ls -l /sys/bus/i2c/devices/i2c-GCTI2607* 2>/dev/null || echo "I2C device not found"
echo ""

echo "==========================================="
echo "Summary"
echo "==========================================="
echo ""

# Check if camera is actually working
if v4l2-ctl --list-subdevs 2>/dev/null | grep -qi gc2607; then
    echo "🎉 SUCCESS! GC2607 is registered as V4L2 subdev!"
    echo ""
    echo "Next steps to capture images:"
    echo "  1. Find the GC2607 subdev number from list above"
    echo "  2. Check supported formats:"
    echo "     v4l2-ctl -d /dev/v4l-subdevX --list-subdev-mbus-codes"
    echo "  3. Configure media pipeline with media-ctl"
    echo "  4. Capture test image with v4l2-ctl"
elif ls /dev/media* 2>/dev/null >/dev/null; then
    echo "⚠️  PARTIAL: Media devices exist but GC2607 not visible"
    echo ""
    echo "Possible issues:"
    echo "  - IPU6 driver needs to be configured to use GC2607"
    echo "  - ACPI tables might not link GC2607 to IPU6"
    echo "  - Async subdev registration might need different approach"
    echo ""
    echo "Check kernel logs above for clues"
else
    echo "❌ FAILED: No media devices found"
    echo ""
    echo "IPU6 driver is not creating media devices."
    echo "This laptop might need:"
    echo "  - Specific IPU6 driver version"
    echo "  - Firmware for IPU6"
    echo "  - Kernel configuration changes"
fi
echo ""

echo "Keep driver loaded for further testing? (y/N)"
read -t 10 -n 1 KEEP
echo ""
if [[ ! $KEEP =~ ^[Yy]$ ]]; then
    echo "Unloading driver..."
    sudo rmmod gc2607
    echo "✅ Driver unloaded"
fi
echo ""
