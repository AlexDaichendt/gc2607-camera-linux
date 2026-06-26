#!/bin/bash
# Investigate IPU Bridge to understand sensor integration

echo "==========================================="
echo "IPU Bridge Investigation"
echo "==========================================="
echo ""

echo "Step 1: Check ipu_bridge kernel messages..."
echo "---------------------------------------"
echo "Looking for bridge initialization and sensor detection:"
sudo dmesg | grep -i "ipu.*bridge\|bridge.*ipu\|bridge.*sensor" | head -50
echo ""

echo "Step 2: Check ipu_bridge module info..."
echo "---------------------------------------"
modinfo ipu_bridge
echo ""

echo "Step 3: Check ipu_bridge parameters..."
echo "---------------------------------------"
ls -la /sys/module/ipu_bridge/parameters/ 2>/dev/null || echo "No parameters found"
if [ -d /sys/module/ipu_bridge/parameters/ ]; then
    echo "Parameters:"
    for param in /sys/module/ipu_bridge/parameters/*; do
        echo "  $(basename $param) = $(cat $param 2>/dev/null)"
    done
fi
echo ""

echo "Step 4: Search for ipu_bridge source/headers..."
echo "---------------------------------------"
KERNEL_SRC="/usr/lib/modules/$(uname -r)/build"
echo "Searching in: $KERNEL_SRC"
find "$KERNEL_SRC" -name "*ipu*bridge*" -o -name "*ipu_bridge*" 2>/dev/null | head -20
echo ""

echo "Step 5: Check ACPI sensor devices..."
echo "---------------------------------------"
echo "All camera-related ACPI devices:"
ls /sys/bus/acpi/devices/ | grep -E "INT3472|GCTI|OVTI|HM|CAM" || echo "No camera ACPI devices found"
echo ""
echo "Details for found devices:"
for dev in /sys/bus/acpi/devices/INT3472* /sys/bus/acpi/devices/GCTI* 2>/dev/null; do
    if [ -d "$dev" ]; then
        echo ""
        echo "Device: $(basename $dev)"
        echo "  Status: $(cat $dev/status 2>/dev/null)"
        echo "  Path: $(cat $dev/path 2>/dev/null)"
        echo "  HID: $(cat $dev/hid 2>/dev/null)"
    fi
done
echo ""

echo "Step 6: Check existing V4L2 i2c subdevs..."
echo "---------------------------------------"
echo "Looking for any registered camera sensors:"
for i2c_dev in /sys/bus/i2c/devices/*; do
    if [ -d "$i2c_dev/video4linux" ]; then
        echo "Found V4L2 device: $(basename $i2c_dev)"
        ls -la "$i2c_dev/video4linux/"
    fi
done
echo ""

echo "Step 7: Check v4l2_async notifiers..."
echo "---------------------------------------"
echo "Looking for async subdev waiting lists:"
sudo dmesg | grep -i "v4l2.*async\|async.*subdev\|async.*notifier" | tail -30
echo ""

echo "Step 8: Check if sensor needs software node..."
echo "---------------------------------------"
echo "Looking for software_node or fwnode references:"
sudo dmesg | grep -i "software.node\|fwnode" | grep -i "gc\|camera\|sensor" | tail -20
echo ""

echo "Step 9: Look for ipu_bridge source code..."
echo "---------------------------------------"
IPU_BRIDGE_SRC=$(find "$KERNEL_SRC" -name "*ipu*bridge*.c" 2>/dev/null | head -1)
if [ -n "$IPU_BRIDGE_SRC" ]; then
    echo "Found source: $IPU_BRIDGE_SRC"
    echo ""
    echo "Checking for sensor table/list:"
    grep -n "struct.*sensor\|{.*\"OV\|{.*\"HM\|{.*\"GC" "$IPU_BRIDGE_SRC" | head -30
    echo ""
    echo "Looking for ACPI matching:"
    grep -n "acpi.*match\|ACPI.*HID" "$IPU_BRIDGE_SRC" | head -20
else
    echo "Source file not found in kernel build tree"
    echo "Trying alternative search..."
    find /usr/src -name "*ipu*bridge*" 2>/dev/null | head -5
fi
echo ""

echo "Step 10: Check for sensor database..."
echo "---------------------------------------"
echo "Looking for known sensor IDs in kernel sources:"
if [ -f "$IPU_BRIDGE_SRC" ]; then
    echo "Sensor entries found:"
    grep -E "\"(OV|HM|GC|ov|hm|gc)[0-9]+\"" "$IPU_BRIDGE_SRC" | head -20
else
    echo "Cannot access source file"
fi
echo ""

echo "==========================================="
echo "Summary & Recommendations"
echo "==========================================="
echo ""
echo "What we're looking for:"
echo "  1. How ipu_bridge discovers sensors (ACPI HIDs)"
echo "  2. List of supported sensors in bridge"
echo "  3. Whether GC2607/GCTI2607 is in the list"
echo "  4. How to add a new sensor to the bridge"
echo ""
echo "If ipu_bridge source is accessible, we can:"
echo "  - Add GC2607 sensor descriptor"
echo "  - Recompile ipu_bridge module"
echo "  - Test camera integration"
echo ""
