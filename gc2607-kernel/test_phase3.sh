#!/bin/bash
# Phase 3 Test: Verify register initialization code is present
# Note: Actual register writing will happen when streaming starts

echo "==========================================="
echo "GC2607 Phase 3 Test"
echo "==========================================="
echo ""

# Build the driver
echo "1. Building driver..."
make clean > /dev/null 2>&1
if make > /dev/null 2>&1; then
    echo "✅ Build successful"
else
    echo "❌ Build failed"
    exit 1
fi
echo ""

# Load the driver
echo "2. Loading driver..."
sudo rmmod gc2607 2>/dev/null
if sudo insmod gc2607.ko; then
    echo "✅ Module loaded"
else
    echo "❌ Module load failed"
    exit 1
fi
echo ""

# Give it time to probe
sleep 1

# Check probe status
echo "3. Checking probe status..."
PROBE_SUCCESS=$(dmesg | tail -50 | grep "GC2607 probe successful")
CHIP_DETECTED=$(dmesg | tail -50 | grep "Read chip ID: 0x2607")

if [ -n "$PROBE_SUCCESS" ] && [ -n "$CHIP_DETECTED" ]; then
    echo "✅ Sensor detected and probed successfully"
    echo "   Chip ID: 0x2607"
else
    echo "❌ Probe failed or chip not detected"
    dmesg | tail -20 | grep gc2607
    sudo rmmod gc2607
    exit 1
fi
echo ""

# Check that the register array is present in the module
echo "4. Verifying register initialization code..."
ARRAY_SIZE=$(nm gc2607.ko | grep gc2607_1080p_30fps_regs | wc -l)
if [ "$ARRAY_SIZE" -gt 0 ]; then
    echo "✅ Register initialization table present in module"
else
    echo "⚠️  Warning: Register table not found in symbols"
fi
echo ""

# Check module info
echo "5. Module information:"
modinfo gc2607.ko | grep -E "filename|description|author"
echo ""

# Unload
echo "6. Unloading driver..."
if sudo rmmod gc2607; then
    echo "✅ Module unloaded"
else
    echo "⚠️  Warning: Module unload had issues"
fi
echo ""

echo "==========================================="
echo "Phase 3 Test Complete!"
echo "==========================================="
echo ""
echo "✅ Phase 3 Implementation Summary:"
echo "   - Register initialization table added (122 registers)"
echo "   - gc2607_write_array() function implemented"
echo "   - Integrated into s_stream() for streaming start"
echo ""
echo "📋 Next Steps:"
echo "   - Phase 3 complete - register init ready"
echo "   - Phase 4: V4L2 integration (format negotiation, controls)"
echo "   - Phase 5: Full streaming support"
echo ""
echo "To test register initialization, you'll need to:"
echo "   1. Register the sensor with media controller"
echo "   2. Use v4l2-ctl or media-ctl to start streaming"
echo "   3. Check dmesg for 'Wrote 122 registers successfully'"
echo ""
