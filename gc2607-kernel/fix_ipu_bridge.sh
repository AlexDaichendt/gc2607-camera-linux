#!/bin/bash
# Properly compile ipu_bridge against Arch kernel headers

set -e

KERNEL_VER="6.17.9-arch1-1"
KERNEL_BUILD="/lib/modules/$KERNEL_VER/build"
MODULE_SRC="$KERNEL_BUILD/drivers/media/pci/intel"
MODULE_NAME="ipu-bridge"

echo "==========================================="
echo "IPU Bridge Fix - Compile Against Arch Kernel"
echo "==========================================="
echo ""

# Check kernel headers exist
if [ ! -d "$KERNEL_BUILD" ]; then
    echo "❌ Kernel headers not found at: $KERNEL_BUILD"
    exit 1
fi

echo "✅ Using Arch kernel headers: $KERNEL_BUILD"
echo ""

# Step 1: Modify ipu-bridge.c in kernel headers tree
echo "Step 1: Modifying ipu-bridge.c..."
echo "---------------------------------------"

if [ ! -f "$MODULE_SRC/ipu-bridge.c" ]; then
    echo "❌ ipu-bridge.c not found at: $MODULE_SRC/ipu-bridge.c"
    exit 1
fi

# Backup original if not already done
if [ ! -f "$MODULE_SRC/ipu-bridge.c.orig" ]; then
    echo "Creating backup of original ipu-bridge.c..."
    sudo cp "$MODULE_SRC/ipu-bridge.c" "$MODULE_SRC/ipu-bridge.c.orig"
    echo "✅ Backup created"
fi

# Check if already modified
if grep -q "GCTI2607" "$MODULE_SRC/ipu-bridge.c"; then
    echo "✅ GC2607 entry already present in ipu-bridge.c"
else
    echo "Adding GC2607 entry to ipu-bridge.c..."
    # Find the line with the sensor definitions and add our entry
    sudo sed -i '/IPU_SENSOR_CONFIG("OVTI.*"/a\        /* GalaxyCore GC2607 */\n        IPU_SENSOR_CONFIG("GCTI2607", 1, 336000000),' "$MODULE_SRC/ipu-bridge.c"
    echo "✅ GC2607 entry added"
fi
echo ""

# Step 2: Create Makefile for single module build
echo "Step 2: Preparing build..."
echo "---------------------------------------"

cat > /tmp/Makefile.ipu_bridge << 'EOF'
obj-m += ipu-bridge.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF

echo "✅ Makefile created"
echo ""

# Step 3: Compile the module
echo "Step 3: Compiling module..."
echo "---------------------------------------"

# Create temp build directory
BUILD_DIR="/tmp/ipu_bridge_build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Copy source file
cp "$MODULE_SRC/ipu-bridge.c" .
cp /tmp/Makefile.ipu_bridge Makefile

echo "Building module..."
make -j$(nproc) 2>&1 | tail -20

if [ -f "$BUILD_DIR/ipu-bridge.ko" ]; then
    echo "✅ Module compiled successfully"
    echo ""
    echo "Module info:"
    modinfo "$BUILD_DIR/ipu-bridge.ko" | head -10
else
    echo "❌ Module compilation failed"
    exit 1
fi
echo ""

# Step 4: Backup and install
echo "Step 4: Installing module..."
echo "---------------------------------------"

SYSTEM_MODULE="/lib/modules/$KERNEL_VER/kernel/drivers/media/pci/intel/ipu-bridge.ko.zst"

# Backup current module if not already backed up recently
BACKUP="$SYSTEM_MODULE.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup: $BACKUP"
sudo cp "$SYSTEM_MODULE" "$BACKUP"
echo "✅ Backup created"
echo ""

# Compress and install
echo "Compressing and installing module..."
zstd -f "$BUILD_DIR/ipu-bridge.ko" -o "/tmp/ipu-bridge.ko.zst"
sudo cp "/tmp/ipu-bridge.ko.zst" "$SYSTEM_MODULE"
rm "/tmp/ipu-bridge.ko.zst"
echo "✅ Module installed"
echo ""

# Step 5: Update dependencies
echo "Step 5: Updating module dependencies..."
echo "---------------------------------------"
sudo depmod -a
echo "✅ Dependencies updated"
echo ""

# Verify
echo "Step 6: Verification..."
echo "---------------------------------------"
echo "Installed module info:"
modinfo ipu_bridge | grep -E "vermagic|filename"
echo ""

# Check for GC2607
if zstd -d -c "$SYSTEM_MODULE" | strings | grep -q "GCTI2607"; then
    echo "✅ GC2607 (GCTI2607) found in installed module!"
else
    echo "⚠️  GC2607 not found - installation may have failed"
fi
echo ""

echo "==========================================="
echo "✅ Installation Complete!"
echo "==========================================="
echo ""
echo "Next steps:"
echo "  1. Load modules:"
echo "     sudo modprobe ipu_bridge"
echo "     sudo modprobe intel-ipu6"
echo "     sudo modprobe intel-ipu6-isys"
echo ""
echo "  2. Check media devices:"
echo "     ls -la /dev/media*"
echo ""
echo "  3. Test GC2607 detection:"
echo "     media-ctl --print-topology | grep -i gc2607"
echo ""
echo "To restore original module:"
echo "  sudo cp $BACKUP $SYSTEM_MODULE"
echo "  sudo depmod -a"
echo ""
