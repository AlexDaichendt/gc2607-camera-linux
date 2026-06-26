#!/bin/bash
# Compile and install modified ipu_bridge module

set -e  # Exit on error

KERNEL_VER="6.17.9-arch1-1"
KERNEL_SRC="$HOME/kernel/dev/linux-6.17.9"
MODULE_NAME="ipu-bridge"
MODULE_PATH="drivers/media/pci/intel"

echo "==========================================="
echo "IPU Bridge Module Compilation"
echo "==========================================="
echo ""
echo "This script will:"
echo "  1. Prepare kernel build environment"
echo "  2. Compile ipu-bridge module"
echo "  3. Backup existing module"
echo "  4. Install new module"
echo "  5. Update module dependencies"
echo ""

# Check if kernel source exists
if [ ! -d "$KERNEL_SRC" ]; then
    echo "❌ Kernel source not found at: $KERNEL_SRC"
    echo "   Run ./setup_ipu_bridge_mod.sh first"
    exit 1
fi

# Check if modification was made
if ! grep -q "GCTI2607" "$KERNEL_SRC/$MODULE_PATH/ipu-bridge.c"; then
    echo "❌ GC2607 entry not found in ipu-bridge.c"
    echo "   Has the file been modified?"
    exit 1
fi

echo "✅ Modified ipu-bridge.c found with GC2607 entry"
echo ""

# Step 1: Prepare build environment
echo "Step 1: Preparing build environment..."
echo "---------------------------------------"
cd "$KERNEL_SRC"

# Copy current kernel config
echo "Copying current kernel configuration..."
if [ -f /proc/config.gz ]; then
    zcat /proc/config.gz > .config
    echo "✅ Copied config from /proc/config.gz"
elif [ -f "/boot/config-$KERNEL_VER" ]; then
    cp "/boot/config-$KERNEL_VER" .config
    echo "✅ Copied config from /boot/config-$KERNEL_VER"
elif [ -f "/lib/modules/$(uname -r)/build/.config" ]; then
    cp "/lib/modules/$(uname -r)/build/.config" .config
    echo "✅ Copied config from kernel build directory"
else
    echo "❌ Cannot find kernel config"
    exit 1
fi
echo ""

# Prepare for module build
echo "Preparing build system (this may take a few minutes)..."
make oldconfig < /dev/null 2>&1 | grep -v "^#" || true
make modules_prepare 2>&1 | tail -5
echo "✅ Build environment ready"
echo ""

# Step 2: Compile the module
echo "Step 2: Compiling ipu-bridge module..."
echo "---------------------------------------"
echo "Building $MODULE_PATH/$MODULE_NAME.ko..."
make M=$MODULE_PATH modules 2>&1 | tail -20
echo ""

# Verify module was built
if [ -f "$KERNEL_SRC/$MODULE_PATH/$MODULE_NAME.ko" ]; then
    echo "✅ Module compiled successfully:"
    ls -lh "$KERNEL_SRC/$MODULE_PATH/$MODULE_NAME.ko"
    echo ""
    echo "Module info:"
    modinfo "$KERNEL_SRC/$MODULE_PATH/$MODULE_NAME.ko" | head -10
else
    echo "❌ Module compilation failed"
    exit 1
fi
echo ""

# Step 3: Backup existing module
echo "Step 3: Backing up existing module..."
echo "---------------------------------------"
SYSTEM_MODULE="/lib/modules/$KERNEL_VER/kernel/$MODULE_PATH/$MODULE_NAME.ko.zst"
if [ -f "$SYSTEM_MODULE" ]; then
    BACKUP="$SYSTEM_MODULE.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up: $SYSTEM_MODULE"
    sudo cp "$SYSTEM_MODULE" "$BACKUP"
    echo "✅ Backup created: $BACKUP"
elif [ -f "/lib/modules/$KERNEL_VER/kernel/$MODULE_PATH/$MODULE_NAME.ko" ]; then
    SYSTEM_MODULE="/lib/modules/$KERNEL_VER/kernel/$MODULE_PATH/$MODULE_NAME.ko"
    BACKUP="$SYSTEM_MODULE.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up: $SYSTEM_MODULE"
    sudo cp "$SYSTEM_MODULE" "$BACKUP"
    echo "✅ Backup created: $BACKUP"
else
    echo "⚠️  No existing module found to backup"
    echo "   This may be the first installation"
fi
echo ""

# Step 4: Install new module
echo "Step 4: Installing new module..."
echo "---------------------------------------"
# Unload if currently loaded
if lsmod | grep -q "^ipu_bridge"; then
    echo "Unloading current ipu_bridge module..."
    sudo rmmod ipu_bridge 2>/dev/null || echo "⚠️  Could not unload (might be in use)"
fi

# Install the new module
echo "Installing to: $SYSTEM_MODULE"
if [[ "$SYSTEM_MODULE" == *.zst ]]; then
    # Compress with zstd if original was compressed
    echo "Compressing module with zstd..."
    zstd -f "$KERNEL_SRC/$MODULE_PATH/$MODULE_NAME.ko" -o "/tmp/$MODULE_NAME.ko.zst"
    sudo cp "/tmp/$MODULE_NAME.ko.zst" "$SYSTEM_MODULE"
    rm "/tmp/$MODULE_NAME.ko.zst"
else
    # Copy uncompressed
    sudo cp "$KERNEL_SRC/$MODULE_PATH/$MODULE_NAME.ko" "$SYSTEM_MODULE"
fi
echo "✅ Module installed"
echo ""

# Step 5: Update module dependencies
echo "Step 5: Updating module dependencies..."
echo "---------------------------------------"
sudo depmod -a "$KERNEL_VER"
echo "✅ Module dependencies updated"
echo ""

# Verify installation
echo "Step 6: Verifying installation..."
echo "---------------------------------------"
echo "Checking installed module:"
modinfo ipu_bridge | grep -E "filename|vermagic|depends|description" || true
echo ""

# Check for GC2607 in module
echo "Checking for GC2607 support:"
if [ -f "$SYSTEM_MODULE" ]; then
    if [[ "$SYSTEM_MODULE" == *.zst ]]; then
        if zstd -d -c "$SYSTEM_MODULE" | strings | grep -q "GCTI2607"; then
            echo "✅ GC2607 (GCTI2607) found in installed module!"
        else
            echo "⚠️  GC2607 not found in module strings"
        fi
    else
        if strings "$SYSTEM_MODULE" | grep -q "GCTI2607"; then
            echo "✅ GC2607 (GCTI2607) found in installed module!"
        else
            echo "⚠️  GC2607 not found in module strings"
        fi
    fi
fi
echo ""

echo "==========================================="
echo "Installation Complete!"
echo "==========================================="
echo ""
echo "Next steps:"
echo "  1. Reload modules:"
echo "     sudo modprobe ipu_bridge"
echo "     sudo rmmod gc2607 && sudo insmod gc2607.ko"
echo ""
echo "  2. Check if GC2607 appears in media topology:"
echo "     media-ctl --print-topology | grep -A 5 gc2607"
echo ""
echo "  3. Run integration test:"
echo "     sudo ./test_camera_streaming.sh"
echo ""
echo "If you need to restore the original module:"
echo "  sudo cp $BACKUP $SYSTEM_MODULE"
echo "  sudo depmod -a"
echo ""
