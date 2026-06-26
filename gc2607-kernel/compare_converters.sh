#!/bin/bash
# Compare old vs improved converter

set -e

echo "=== Comparing Converters ==="
echo ""

# Set optimal values
echo "Setting optimal exposure/gain (1335/253)..."
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=253

# Capture one raw image
echo "Capturing raw image..."
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=compare.raw 2>/dev/null

echo ""
echo "Converting with both methods..."

# Old method
echo "1. Old converter (simple)..."
./view_raw_bright.py compare.raw 1.0 > /dev/null 2>&1
mv compare.png old_simple.png
echo "   ✅ Saved: old_simple.png"

# New method with white balance
echo "2. New converter (with white balance)..."
./view_raw_improved.py compare.raw 1.0 on > /dev/null 2>&1
mv compare.png new_wb_on.png
echo "   ✅ Saved: new_wb_on.png"

# New method without white balance (for comparison)
echo "3. New converter (no white balance)..."
./view_raw_improved.py compare.raw 1.0 off > /dev/null 2>&1
mv compare.png new_wb_off.png
echo "   ✅ Saved: new_wb_off.png"

echo ""
echo "=== Comparison ==="
echo ""
echo "View all three:"
echo "  feh old_simple.png new_wb_on.png new_wb_off.png"
echo ""
echo "  old_simple.png   - Current simple demosaicing"
echo "  new_wb_on.png    - With automatic white balance"
echo "  new_wb_off.png   - Without white balance"
echo ""
echo "Check if new_wb_on.png has less green tint!"
