#!/bin/bash

echo "=== Finding which INT3472 belongs to GCTI2607 ==="
echo

# Check status of each INT3472 device
echo "INT3472 Device Status (15 = enabled):"
for dev in /sys/bus/acpi/devices/INT3472*; do
    if [ -d "$dev" ]; then
        name=$(basename "$dev")
        status=$(cat "$dev/status" 2>/dev/null)
        path=$(cat "$dev/path" 2>/dev/null)
        has_physical=$([ -L "$dev/physical_node" ] && echo "YES" || echo "NO")
        echo "  $name: status=$status, path=$path, bound=$has_physical"
    fi
done

echo
echo "=== GC2607 Sensor Info ==="
gcdev="/sys/bus/acpi/devices/GCTI2607:00"
if [ -d "$gcdev" ]; then
    echo "Status: $(cat $gcdev/status 2>/dev/null)"
    echo "Path: $(cat $gcdev/path 2>/dev/null)"
fi

echo
echo "=== Checking ACPI Table for Dependencies ==="
echo "Need to extract DSDT to see _DEP (dependencies) between GCTI2607 and INT3472"
echo "This requires: sudo acpidump -b && iasl -d *.dat"
echo

# Alternative: Check kernel messages for INT3472 probe attempts
echo "=== Recent INT3472 kernel messages ==="
sudo dmesg | grep -i int3472 | tail -20

echo
echo "=== Checking for GPIO chips from INT3472 ==="
ls -la /sys/class/gpio/ 2>/dev/null || echo "No GPIO chips visible"

echo
echo "=== All available regulators ==="
for reg in /sys/class/regulator/regulator.*; do
    if [ -d "$reg" ]; then
        name=$(basename "$reg")
        rname=$(cat "$reg/name" 2>/dev/null)
        status=$(cat "$reg/status" 2>/dev/null)
        echo "  $name: $rname (status: $status)"
    fi
done
