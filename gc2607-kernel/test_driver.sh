#!/bin/bash
# Test script for GC2607 driver Phase 2

set -e

echo "=== GC2607 Driver Test Script ==="
echo ""

# Check if module exists
if [ ! -f "gc2607.ko" ]; then
    echo "ERROR: gc2607.ko not found. Run 'make' first."
    exit 1
fi

# Unload old module if loaded
if lsmod | grep -q gc2607; then
    echo "Unloading old gc2607 module..."
    sudo rmmod gc2607 || true
    sleep 1
fi

echo "Loading gc2607.ko..."
sudo insmod gc2607.ko

echo ""
echo "Waiting for probe to complete..."
sleep 2

echo ""
echo "=== Driver Messages (last 60 lines) ==="
sudo dmesg | tail -60 | grep -E "(gc2607|i2c-GCTI2607)" || echo "No gc2607 messages found"

echo ""
echo "=== Module Status ==="
lsmod | grep gc2607 || echo "Module not loaded!"

echo ""
echo "=== Device Binding ==="
ls -la /sys/bus/i2c/drivers/gc2607/ 2>/dev/null || echo "Driver not bound to any device"

echo ""
echo "=== I2C Device ==="
ls -la /sys/bus/i2c/devices/i2c-GCTI2607:00/ 2>/dev/null | head -5

echo ""
echo "=== Runtime PM Status ==="
cat /sys/bus/i2c/devices/i2c-GCTI2607:00/power/runtime_status 2>/dev/null || echo "N/A"

echo ""
echo "=== Test Complete ==="
echo ""
echo "To view full kernel log: sudo dmesg | less"
echo "To unload driver: sudo rmmod gc2607"
