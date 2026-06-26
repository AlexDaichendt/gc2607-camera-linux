#!/bin/bash
# Quick comprehensive test of GC2607 driver and INT3472 integration

echo "========================================="
echo "GC2607 Driver Quick Test"
echo "========================================="
echo

# Check if module is already loaded
if lsmod | grep -q gc2607; then
    echo "⚠️  gc2607 module already loaded. Unloading..."
    sudo rmmod gc2607 2>/dev/null
fi

# Rebuild
echo "1. Building driver..."
make clean > /dev/null 2>&1
make > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi
echo "✅ Build successful"
echo

# Load driver
echo "2. Loading driver..."
sudo insmod gc2607.ko
if [ $? -ne 0 ]; then
    echo "❌ Failed to load module!"
    exit 1
fi
echo "✅ Module loaded"
echo

# Wait for probe
sleep 1

# Collect results
echo "3. Collecting results..."
echo

echo "=== Driver Messages ==="
sudo dmesg | grep gc2607 | tail -30

echo
echo "=== Regulator Users (was 2, now should be 3 if driver got it) ==="
cat /sys/class/regulator/regulator.1/num_users

echo
echo "=== GC2607 I2C Device ==="
if [ -d /sys/bus/i2c/devices/5-0037 ]; then
    echo "✅ Device exists at /sys/bus/i2c/devices/5-0037"
    ls -la /sys/bus/i2c/devices/5-0037/ | grep -E "driver|power|name"
else
    echo "❌ Device not found at /sys/bus/i2c/devices/5-0037"
fi

echo
echo "=== I2C Bus Scan (UU = driver bound, 37 = device present, -- = no device) ==="
sudo i2cdetect -y 5 2>&1 | grep -A10 "^ "

echo
echo "=== Status Summary ==="
if sudo dmesg | tail -50 | grep -q "GC2607 chip detected successfully"; then
    echo "🎉 SUCCESS! Chip detected at 0x2607"
    echo "    → Ready for Phase 3: Register initialization"
elif sudo dmesg | tail -50 | grep -q "GC2607 probe started"; then
    if sudo dmesg | tail -50 | grep -q "Failed to read chip ID.*-121"; then
        echo "⚠️  PARTIAL: Driver loaded but sensor not responding"
        echo "    → Power control issue - need to investigate INT3472 GPIOs"
    elif sudo dmesg | tail -50 | grep -q "Regulators not available"; then
        echo "⚠️  PARTIAL: Driver loaded but no resources found"
        echo "    → Need to add resource mappings (GPIO lookup table, etc.)"
    else
        echo "⚠️  PARTIAL: Driver loaded but unknown state"
        echo "    → Check dmesg logs above for details"
    fi
else
    echo "❌ FAILED: Driver didn't probe"
    echo "    → Check dmesg for errors"
fi

echo
echo "=== Unloading driver ==="
sudo rmmod gc2607
echo "✅ Module unloaded"

echo
echo "========================================="
echo "Test complete! See messages above."
echo "========================================="
