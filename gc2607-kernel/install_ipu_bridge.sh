#!/bin/bash
# Install the modified ipu_bridge module

set -e

KERNEL_VER="6.17.9-arch1-1"
NEW_MODULE="/home/abbood/kernel/dev/linux-6.17.9/drivers/media/pci/intel/ipu-bridge.ko"
SYSTEM_MODULE="/lib/modules/$KERNEL_VER/kernel/drivers/media/pci/intel/ipu-bridge.ko.zst"

echo "==========================================="
echo "Installing Modified IPU Bridge Module"
echo "==========================================="
echo ""

# Check if new module exists
if [ ! -f "$NEW_MODULE" ]; then
    echo "❌ Compiled module not found: $NEW_MODULE"
    exit 1
fi

# Verify GC2607 support
if ! strings "$NEW_MODULE" | grep -q "GCTI2607"; then
    echo "❌ GC2607 support not found in module"
    exit 1
fi
echo "✅ Found GC2607 (GCTI2607) in compiled module"
echo ""

# Unload module if loaded
echo "Checking if ipu_bridge is currently loaded..."
if lsmod | grep -q "^ipu_bridge"; then
    echo "Unloading ipu_bridge module..."
    rmmod ipu_bridge || {
        echo "⚠️  Could not unload ipu_bridge (might be in use)"
        echo "   You may need to:"
        echo "   1. Unload dependent modules (like intel-ipu6)"
        echo "   2. Reboot after installation"
    }
else
    echo "✅ Module not currently loaded"
fi
echo ""

# Backup existing module
echo "Backing up existing module..."
BACKUP="$SYSTEM_MODULE.backup.$(date +%Y%m%d_%H%M%S)"
cp "$SYSTEM_MODULE" "$BACKUP"
echo "✅ Backup created: $BACKUP"
echo ""

# Compress and install new module
echo "Compressing new module with zstd..."
zstd -f "$NEW_MODULE" -o /tmp/ipu-bridge.ko.zst
echo "✅ Module compressed"
echo ""

echo "Installing new module..."
cp /tmp/ipu-bridge.ko.zst "$SYSTEM_MODULE"
rm /tmp/ipu-bridge.ko.zst
echo "✅ Module installed to: $SYSTEM_MODULE"
echo ""

# Verify installation
echo "Verifying installation..."
if zstd -d -c "$SYSTEM_MODULE" | strings | grep -q "GCTI2607"; then
    echo "✅ GC2607 (GCTI2607) confirmed in installed module!"
else
    echo "⚠️  Warning: GCTI2607 not found in installed module"
fi
echo ""

# Update module dependencies
echo "Updating module dependencies..."
depmod -a "$KERNEL_VER"
echo "✅ Module dependencies updated"
echo ""

echo "==========================================="
echo "Installation Complete!"
echo "==========================================="
echo ""
echo "The modified ipu_bridge module has been installed."
echo ""
echo "Next steps:"
echo ""
echo "1. Load the new module:"
echo "   sudo modprobe ipu_bridge"
echo ""
echo "2. Reload your GC2607 driver:"
echo "   sudo rmmod gc2607"
echo "   sudo insmod gc2607.ko"
echo ""
echo "3. Check if GC2607 appears in media topology:"
echo "   media-ctl --print-topology | grep -i gc2607"
echo ""
echo "4. If successful, verify full topology:"
echo "   media-ctl -d /dev/media0 --print-topology"
echo ""
echo "If you need to restore the original module:"
echo "   sudo cp $BACKUP $SYSTEM_MODULE"
echo "   sudo depmod -a"
echo "   sudo modprobe -r ipu_bridge && sudo modprobe ipu_bridge"
echo ""
