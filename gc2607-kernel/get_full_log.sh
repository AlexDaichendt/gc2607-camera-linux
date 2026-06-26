#!/bin/bash
# Get full detailed kernel log for gc2607

echo "=== Full GC2607 Kernel Messages ==="
echo ""

# Get all gc2607 messages since boot
sudo dmesg | grep -A 5 -B 2 "gc2607" | tail -100

echo ""
echo "=== Filtering for our debug messages ==="
sudo dmesg | grep -E "(GC2607 probe|Resources|Regulators|GPIO|Clock|power)" | tail -50
