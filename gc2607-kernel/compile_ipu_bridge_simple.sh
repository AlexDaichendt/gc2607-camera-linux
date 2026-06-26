#!/bin/bash
# Simple single-module compilation for ipu-bridge

set -e

KERNEL_VER="6.17.9-arch1-1"
KERNEL_SRC="$HOME/kernel/dev/linux-6.17.9"
SOURCE_FILE="$KERNEL_SRC/drivers/media/pci/intel/ipu-bridge.c"

echo "==========================================="
echo "IPU Bridge - Single Module Build"
echo "==========================================="
echo ""

# Check source exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Source not found: $SOURCE_FILE"
    exit 1
fi

# Verify GC2607 entry
if ! grep -q "GCTI2607" "$SOURCE_FILE"; then
    echo "❌ GCTI2607 not found in source file"
    exit 1
fi
echo "✅ GC2607 entry verified in source"
echo ""

# Create temp build directory
BUILD_DIR="/tmp/ipu_bridge_build_$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "Step 1: Preparing source..."
echo "---------------------------------------"
cp "$SOURCE_FILE" .
echo "✅ Source copied"
echo ""

# Create simple Makefile for single module
echo "Step 2: Creating Makefile..."
echo "---------------------------------------"
cat > Makefile << 'EOF'
obj-m += ipu-bridge.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF
echo "✅ Makefile created"
echo ""

echo "Step 3: Compiling module..."
echo "---------------------------------------"
make -j$(nproc)

if [ ! -f "ipu-bridge.ko" ]; then
    echo "❌ Compilation failed"
    exit 1
fi

echo "✅ Module compiled successfully"
echo ""
echo "Module info:"
modinfo ipu-bridge.ko | grep -E "filename|vermagic|depends"
echo ""

# Verify GC2607 is in compiled module
if strings ipu-bridge.ko | grep -q "GCTI2607"; then
    echo "✅ GCTI2607 found in compiled module"
else
    echo "⚠️  GCTI2607 not found in module (unexpected)"
fi
echo ""

echo "Step 4: Installing module..."
echo "---------------------------------------"

SYSTEM_MODULE="/lib/modules/$KERNEL_VER/kernel/drivers/media/pci/intel/ipu-bridge.ko.zst"

# Backup
BACKUP="$SYSTEM_MODULE.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup: $BACKUP"
sudo cp "$SYSTEM_MODULE" "$BACKUP"
echo "✅ Backup created"
echo ""

# Compress and install
echo "Compressing and installing..."
zstd -f ipu-bridge.ko -o ipu-bridge.ko.zst
sudo cp ipu-bridge.ko.zst "$SYSTEM_MODULE"
echo "✅ Module installed"
echo ""

# Update dependencies
echo "Updating module dependencies..."
sudo depmod -a
echo "✅ Dependencies updated"
echo ""

echo "==========================================="
echo "✅ Installation Complete!"
echo "==========================================="
echo ""
echo "Compiled module saved to: $BUILD_DIR/ipu-bridge.ko"
echo ""
echo "Next steps:"
echo "  1. Reload modules:"
echo "     sudo modprobe -r ipu_bridge"
echo "     sudo modprobe ipu_bridge"
echo ""
echo "  2. Load GC2607 driver:"
echo "     sudo insmod gc2607.ko"
echo ""
echo "  3. Test detection:"
echo "     media-ctl --print-topology | grep -i gc2607"
echo ""
