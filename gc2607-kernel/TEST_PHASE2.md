# Phase 2 Testing Instructions

## What's New in Phase 2

Phase 2 adds complete power management support:

✅ **Power Resources Acquisition**
- GPIO control (reset, powerdown)
- Regulator management (avdd, dovdd, dvdd)
- Clock management (xclk/MCLK)

✅ **Power Sequences**
- Power-on: Regulators → Clock → De-assert reset → Wait for boot
- Power-off: Assert reset → Disable clock → Disable regulators

✅ **Runtime PM Integration**
- Automatic power management via runtime PM framework
- Power on during s_stream(enable=1)
- Power off during s_stream(enable=0)

✅ **Chip ID Detection**
- Power on sensor during probe
- Read chip ID registers (0x03f0, 0x03f1)
- Verify chip ID is 0x2607
- Power off after detection

## Testing Commands

```bash
# 1. Load the driver
sudo insmod gc2607.ko

# 2. Check probe logs (look for power-on sequence and chip ID detection)
sudo dmesg | tail -50

# 3. Check runtime PM status
cat /sys/bus/i2c/devices/i2c-GCTI2607\:00/power/runtime_status

# 4. Check if sensor was detected
ls -l /sys/bus/i2c/drivers/gc2607/

# 5. Unload when done
sudo rmmod gc2607
```

## Expected Success Output

If INT3472 provides all resources correctly, you should see:

```
gc2607 i2c-GCTI2607:00: GC2607 probe started
gc2607 i2c-GCTI2607:00: Resources acquired successfully
gc2607 i2c-GCTI2607:00:   Clock rate: 19200000 Hz
gc2607 i2c-GCTI2607:00: Sensor powered on successfully
gc2607 i2c-GCTI2607:00: GC2607 chip ID detected: 0x2607
gc2607 i2c-GCTI2607:00: Sensor powered off
gc2607 i2c-GCTI2607:00: GC2607 probe successful
gc2607 i2c-GCTI2607:00:   I2C address: 0x37
gc2607 i2c-GCTI2607:00:   I2C adapter: Synopsys DesignWare I2C adapter
```

## Expected Failure Scenarios

### Scenario 1: Missing Regulators
If INT3472 doesn't provide regulator names:
```
gc2607 i2c-GCTI2607:00: Failed to get regulators: -2
```

**Fix**: INT3472 might use different supply names. Check:
```bash
ls /sys/class/regulator/
cat /sys/devices/.../INT3472*/regulator.*/name
```

We may need to adjust supply names or make them optional.

### Scenario 2: Missing GPIO
If reset GPIO is not provided:
```
gc2607 i2c-GCTI2607:00: Failed to get reset GPIO: -2
```

**Fix**: Check ACPI _CRS resources for GPIO. May need to use GPIO lookup table.

### Scenario 3: Wrong Chip ID
If I2C communication works but chip ID is wrong:
```
gc2607 i2c-GCTI2607:00: Wrong chip ID: expected 0x2607, got 0xXXXX
```

**Fix**: This could mean:
- Sensor is not actually a GC2607
- Different I2C address needed
- Power sequence timing issue

### Scenario 4: I2C Communication Failed
If sensor is not responding on I2C:
```
gc2607 i2c-GCTI2607:00: Failed to read reg 0x03f0: -121
```

**Fix**:
- Check I2C bus with `i2cdetect -y 5`
- Verify sensor is powered (check regulator/GPIO states)
- May need to adjust power-on timing delays

## Troubleshooting Commands

```bash
# Check ACPI resources
cat /sys/bus/acpi/devices/GCTI2607\:00/status
cat /sys/bus/acpi/devices/GCTI2607\:00/path

# Check INT3472 PMIC
ls -la /sys/bus/acpi/devices/INT3472\:01/

# Check available regulators
ls /sys/class/regulator/
cat /sys/class/regulator/regulator.*/name

# Check GPIO chips
ls /sys/class/gpio/
cat /sys/kernel/debug/gpio

# Scan I2C bus (may show 0x37 as UU if driver bound)
sudo i2cdetect -y 5

# Monitor kernel messages in real-time
sudo dmesg -w
```

## Next Steps After Success

If Phase 2 succeeds:
- **Phase 3**: Register initialization (write 280+ registers from reference driver)
- **Phase 4**: Format/resolution configuration
- **Phase 5**: Streaming support with actual video data

If Phase 2 fails:
- Analyze error messages
- Check INT3472 ACPI resources
- May need to adjust resource acquisition strategy
