#!/bin/bash

echo "=== INT3472:01 (GC2607 PMIC) Resource Analysis ==="
echo

INT3472_DEV="/sys/devices/pci0000:00/INT3472:01"
GC2607_DEV="/sys/bus/i2c/devices/5-0037"

echo "1. Privacy LED (confirms this INT3472 is for GC2607):"
ls -la "$INT3472_DEV/leds/"
echo

echo "2. Regulator provided:"
cat /sys/class/regulator/regulator.1/name
echo "   - Number of users: $(cat /sys/class/regulator/regulator.1/num_users)"
echo "   - State: $(cat /sys/class/regulator/regulator.1/state 2>/dev/null || echo 'unknown')"
echo

echo "3. Looking for GPIO chips created by INT3472:"
for gpiochip in /sys/class/gpio/gpiochip*; do
    if [ -d "$gpiochip" ]; then
        label=$(cat "$gpiochip/label" 2>/dev/null)
        if echo "$label" | grep -qi "int3472\|INT3472"; then
            echo "   Found: $gpiochip -> $label"
            echo "     Base: $(cat $gpiochip/base)"
            echo "     Ngpio: $(cat $gpiochip/ngpio)"
        fi
    fi
done

echo

echo "4. Checking if GC2607 I2C device exists:"
if [ -d "$GC2607_DEV" ]; then
    echo "   YES: $GC2607_DEV exists"
    ls -la "$GC2607_DEV/"

    echo
    echo "   Power state:"
    cat "$GC2607_DEV/power/runtime_status" 2>/dev/null || echo "   Not available"
else
    echo "   NO: $GC2607_DEV not found (driver not loaded?)"
fi

echo

echo "5. Checking kernel driver binding:"
echo "   INT3472:01 driver:"
readlink "$INT3472_DEV/driver" 2>/dev/null || echo "   Not bound"

if [ -d "$GC2607_DEV" ]; then
    echo "   GC2607 driver:"
    readlink "$GC2607_DEV/driver" 2>/dev/null || echo "   Not bound"
fi

echo

echo "6. Looking for consumer/supplier relationships:"
if [ -d "$GC2607_DEV" ]; then
    for link in "$GC2607_DEV/supplier:"*; do
        if [ -L "$link" ]; then
            echo "   $(basename $link) -> $(readlink $link)"
        fi
    done
fi

echo

echo "=== Recommendation ==="
echo "The INT3472:01 provides:"
echo "  - regulator.1 (INT3472:01-avdd)"
echo "  - Privacy LED (GCTI2607_00::privacy_led)"
echo "  - Possibly GPIOs (need to check GPIO chips above)"
echo
echo "To make the GC2607 driver use these resources, we may need to:"
echo "  1. Add explicit regulator consumer mapping"
echo "  2. Add GPIO lookup table for reset/powerdown pins"
echo "  3. Add clock lookup if INT3472 provides clock"
echo
