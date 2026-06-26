#!/bin/bash
# Reload IPU modules to use the new ipu_bridge with GC2607 support

echo "==========================================="
echo "Reloading IPU6 Modules"
echo "==========================================="
echo ""

echo "Step 1: Unloading all IPU and camera modules..."
echo "---------------------------------------"

# Unload in correct order (dependent modules first)
echo "Unloading gc2607..."
rmmod gc2607 2>/dev/null || echo "  gc2607 not loaded"

echo "Unloading intel_ipu6_psys..."
rmmod intel_ipu6_psys 2>/dev/null || echo "  intel_ipu6_psys not loaded"

echo "Unloading intel_ipu6_isys..."
rmmod intel_ipu6_isys 2>/dev/null || echo "  intel_ipu6_isys not loaded"

echo "Unloading intel_ipu6..."
rmmod intel_ipu6 2>/dev/null || echo "  intel_ipu6 not loaded"

echo "Unloading ipu_bridge..."
rmmod ipu_bridge 2>/dev/null || echo "  ipu_bridge not loaded"

echo "✅ Modules unloaded"
echo ""

echo "Step 2: Reloading modules with new ipu_bridge..."
echo "---------------------------------------"

echo "Loading ipu_bridge (NEW VERSION with GC2607)..."
modprobe ipu_bridge
echo "✅ ipu_bridge loaded"

echo "Loading intel_ipu6..."
modprobe intel_ipu6
echo "✅ intel_ipu6 loaded"

echo "Loading intel_ipu6_isys..."
modprobe intel_ipu6_isys
echo "✅ intel_ipu6_isys loaded"

echo "Loading intel_ipu6_psys..."
modprobe intel_ipu6_psys 2>/dev/null || echo "  (psys optional, skipping)"

echo ""
echo "Step 3: Loading GC2607 driver..."
echo "---------------------------------------"
cd /home/abbood/dev/camera-driver-dev/gc2607-v4l2-driver
insmod gc2607.ko
echo "✅ gc2607 loaded"
echo ""

echo "Step 4: Checking kernel messages..."
echo "---------------------------------------"
dmesg | tail -30 | grep -E "ipu_bridge|gc2607|GCTI2607"
echo ""

echo "==========================================="
echo "Modules Reloaded!"
echo "==========================================="
echo ""
echo "Now check if GC2607 appears in media topology:"
echo "  media-ctl --print-topology | grep -i gc2607"
echo ""
echo "Or view full topology:"
echo "  media-ctl -d /dev/media0 --print-topology"
echo ""
