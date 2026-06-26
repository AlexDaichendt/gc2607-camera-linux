#!/bin/bash
# Check what resources INT3472 PMIC provides

echo "=== INT3472 PMIC Status ==="
ls -la /sys/bus/acpi/devices/INT3472*/

echo -e "\n=== INT3472 Driver Binding ==="
ls -la /sys/bus/platform/drivers/int3472*/

echo -e "\n=== Available Regulators ==="
ls -la /sys/class/regulator/
echo ""
for reg in /sys/class/regulator/regulator.*; do
    if [ -d "$reg" ]; then
        echo "$(basename $reg): $(cat $reg/name 2>/dev/null || echo 'no name')"
    fi
done

echo -e "\n=== GPIO Chips ==="
ls /sys/class/gpio/ | grep chip

echo -e "\n=== Camera Sensor I2C Device ==="
ls -la /sys/bus/i2c/devices/i2c-GCTI2607*/

echo -e "\n=== I2C-5 Bus Scan (may show UU if driver bound) ==="
i2cdetect -y 5 2>/dev/null || echo "i2c-tools not installed or need sudo"

echo -e "\n=== Check ACPI _CRS for GCTI2607 ==="
grep -r "GCTI2607" /sys/firmware/acpi/tables/ 2>/dev/null || echo "Need sudo for ACPI tables"
