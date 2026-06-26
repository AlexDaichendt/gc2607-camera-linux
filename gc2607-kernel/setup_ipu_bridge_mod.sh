#!/bin/bash
# Download kernel source and prepare ipu_bridge modification

set -e  # Exit on error

KERNEL_VER="6.17.9"
KERNEL_DIR="$HOME/kernel/dev"
KERNEL_SRC="$KERNEL_DIR/linux-$KERNEL_VER"
IPU_BRIDGE_FILE=""

echo "==========================================="
echo "IPU Bridge Modification Setup"
echo "==========================================="
echo ""
echo "This script will:"
echo "  1. Create ~/kernel/dev directory"
echo "  2. Download Linux kernel $KERNEL_VER source"
echo "  3. Extract the source"
echo "  4. Locate ipu-bridge.c"
echo "  5. Show what needs to be modified"
echo ""

# Step 1: Create directory
echo "Step 1: Creating directory structure..."
echo "---------------------------------------"
mkdir -p "$KERNEL_DIR"
cd "$KERNEL_DIR"
echo "✅ Created: $KERNEL_DIR"
echo ""

# Step 2: Download kernel source
echo "Step 2: Downloading kernel source..."
echo "---------------------------------------"
KERNEL_TAR="linux-$KERNEL_VER.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/$KERNEL_TAR"

if [ -f "$KERNEL_TAR" ]; then
    echo "⚠️  $KERNEL_TAR already exists, skipping download"
else
    echo "Downloading from: $KERNEL_URL"
    wget "$KERNEL_URL" || {
        echo "❌ Download failed. Trying alternative mirror..."
        wget "https://kernel.org/pub/linux/kernel/v6.x/$KERNEL_TAR"
    }
    echo "✅ Downloaded: $KERNEL_TAR"
fi
echo ""

# Step 3: Extract
echo "Step 3: Extracting kernel source..."
echo "---------------------------------------"
if [ -d "$KERNEL_SRC" ]; then
    echo "⚠️  $KERNEL_SRC already exists"
    echo "Remove it? (y/N)"
    read -n 1 REMOVE
    echo ""
    if [[ $REMOVE =~ ^[Yy]$ ]]; then
        rm -rf "$KERNEL_SRC"
        echo "Extracting..."
        tar -xf "$KERNEL_TAR"
        echo "✅ Extracted to: $KERNEL_SRC"
    else
        echo "Keeping existing directory"
    fi
else
    echo "Extracting..."
    tar -xf "$KERNEL_TAR"
    echo "✅ Extracted to: $KERNEL_SRC"
fi
echo ""

# Step 4: Find ipu-bridge.c
echo "Step 4: Locating ipu-bridge.c..."
echo "---------------------------------------"
cd "$KERNEL_SRC"
IPU_BRIDGE_FILE=$(find . -name "*ipu*bridge*.c" -o -name "ipu-bridge.c" | head -1)

if [ -n "$IPU_BRIDGE_FILE" ]; then
    echo "✅ Found: $IPU_BRIDGE_FILE"
    IPU_BRIDGE_PATH="$KERNEL_SRC/$IPU_BRIDGE_FILE"
else
    echo "❌ Could not find ipu-bridge.c"
    echo "Searching more broadly..."
    find . -path "*/intel/*" -name "*.c" | grep -i bridge
    exit 1
fi
echo ""

# Step 5: Analyze the file
echo "Step 5: Analyzing ipu-bridge.c..."
echo "---------------------------------------"
echo "File location: $IPU_BRIDGE_PATH"
echo ""
echo "Looking for sensor configuration array..."
echo ""

# Find the sensor config array
if grep -n "IPU_SENSOR_CONFIG\|sensor.*config\|supported.*sensor" "$IPU_BRIDGE_PATH" | head -20; then
    echo ""
    echo "✅ Found sensor configuration section"
else
    echo "⚠️  Could not find sensor config array automatically"
fi
echo ""

# Step 6: Show what needs to be added
echo "Step 6: Modification Instructions"
echo "==========================================="
echo ""
echo "📝 What to add to ipu-bridge.c:"
echo ""
echo "Find the sensor configuration array (look for lines like):"
echo '  IPU_SENSOR_CONFIG("OVTI01A0", ...'
echo '  IPU_SENSOR_CONFIG("OVTI8856", ...'
echo ""
echo "Add this line to the array:"
echo '  IPU_SENSOR_CONFIG("GCTI2607", 1, 336000000),'
echo ""
echo "Details:"
echo '  - "GCTI2607" = ACPI HID for GC2607 sensor'
echo "  - 1 = number of link frequencies"
echo "  - 336000000 = link frequency in Hz (336 MHz)"
echo ""
echo "==========================================="
echo ""

# Step 7: Create a backup and show next steps
echo "Step 7: Next Steps"
echo "==========================================="
echo ""
echo "Ready to modify the file!"
echo ""
echo "Option A - Manual Edit:"
echo "  1. Open file: $IPU_BRIDGE_PATH"
echo "  2. Find sensor config array"
echo "  3. Add GC2607 entry"
echo "  4. Save and close"
echo ""
echo "Option B - Automated Patch:"
echo "  Run: ./patch_ipu_bridge.sh"
echo "  (Will be created next)"
echo ""
echo "After modification:"
echo "  1. Recompile ipu_bridge module"
echo "  2. Install new module"
echo "  3. Reload and test"
echo ""

# Offer to show the exact location
echo "Would you like to see the sensor array now? (y/N)"
read -t 10 -n 1 SHOW
echo ""
if [[ $SHOW =~ ^[Yy]$ ]]; then
    echo ""
    echo "=== Sensor Configuration Array ==="
    echo ""
    grep -B 5 -A 20 "IPU_SENSOR_CONFIG" "$IPU_BRIDGE_PATH" | head -40
    echo ""
fi

echo "==========================================="
echo "Setup Complete!"
echo "==========================================="
echo ""
echo "Kernel source ready at:"
echo "  $KERNEL_SRC"
echo ""
echo "IPU bridge file:"
echo "  $IPU_BRIDGE_PATH"
echo ""
echo "Next: Modify the file and recompile module"
echo ""
