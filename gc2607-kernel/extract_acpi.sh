#!/bin/bash

echo "=== Extracting ACPI Tables ==="
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

echo "Dumping ACPI tables..."
sudo acpidump -b

echo
echo "Decompiling DSDT..."
if [ -f dsdt.dat ]; then
    sudo iasl -d dsdt.dat 2>&1 | head -20

    if [ -f dsdt.dsl ]; then
        echo
        echo "=== Searching for GCTI2607 in DSDT ==="
        grep -A 30 "GCTI2607" dsdt.dsl || echo "GCTI2607 not found"

        echo
        echo "=== Searching for LNK0 device ==="
        grep -B 5 -A 40 'Device.*LNK0' dsdt.dsl || echo "LNK0 not found"

        echo
        echo "=== Full DSDT saved to: $TMPDIR/dsdt.dsl ==="
        echo "You can examine it with: less $TMPDIR/dsdt.dsl"
    fi
else
    echo "ERROR: dsdt.dat not found. Do you have acpica-tools installed?"
    echo "Install with: sudo pacman -S acpica"
fi

cd - > /dev/null
