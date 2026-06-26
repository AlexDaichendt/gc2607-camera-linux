# INT3472 PMIC Integration Analysis

## Summary of Findings

Through systematic investigation, we've confirmed that **INT3472:01 is the PMIC for the GC2607 camera sensor**.

### Evidence
1. **Privacy LED naming**: `GCTI2607_00::privacy_led` - directly references the GC2607 sensor
2. **ACPI paths**:
   - GC2607 sensor: `\_SB_.PC00.LNK0` (status=15, enabled)
   - INT3472:01: `\_SB_.PC00.DSC0` (status=15, enabled, driver bound)
3. **Resources provided by INT3472:01**:
   - Regulator: `regulator.1` named `INT3472:01-avdd`
   - Privacy LED: `GCTI2607_00::privacy_led`
   - Possibly GPIOs and clocks (not yet identified)

## Current Status

### INT3472:01 State
- ✅ Driver loaded: `intel_skl_int3472_discrete`
- ✅ Regulator created: `INT3472:01-avdd`
- ✅ Regulator enabled (2 users currently)
- ✅ LED device created
- ⚠️  No visible GPIO chips in `/sys/class/gpio/`

### GC2607 Driver State
When the GC2607 driver loads, it reports:
```
gc2607: Regulators not available (-2), assuming INT3472 handles power
gc2607: No reset GPIO, assuming INT3472 handles it
gc2607: No clock from platform, assuming INT3472 provides it
```

This means the driver can't find the resources through standard APIs.

## The Problem

The INT3472 PMIC provides resources, but they're not being automatically connected to the GC2607 driver. This is a common issue on laptop platforms where ACPI doesn't fully describe the resource relationships.

### Why Resources Aren't Found

1. **Regulators**: The INT3472 creates a regulator, but there's no ACPI mapping telling the GC2607 driver to use it
2. **GPIOs**: INT3472 may provide GPIOs, but:
   - They might be consumed internally (not exposed as GPIO chips)
   - They might need explicit ACPI GPIO resource declarations
   - The names might not match what the driver expects ("reset", "powerdown")
3. **Clock**: INT3472 might provide a clock through:
   - A GPIO-controlled fixed-rate clock
   - Direct ACPI clock resource
   - Internal handling without exposing to drivers

## How INT3472 Works

The `intel_skl_int3472_discrete` driver:

1. **Parses ACPI _DSM** (Device-Specific Method) to discover GPIO functions
2. **Creates resources** based on GPIO types:
   - Type 0x00: Reset GPIO
   - Type 0x01: Powerdown GPIO
   - Type 0x0b: Power enable (creates gpio-regulator)
   - Type 0x0c: Clock enable (creates gpio-controlled clock)
   - Type 0x0d: Privacy LED
3. **Registers** these resources so sensor drivers can use them

### The Regulator Puzzle

The regulator `INT3472:01-avdd` has 2 users and is enabled. Possible explanations:

1. **Dummy user**: The regulator framework may count the regulator itself as a user
2. **ACPI consumer**: ACPI might have pre-enabled it
3. **Another driver**: Some other component might be using it
4. **IPU6 driver**: The camera bridge driver might have claimed it

## Solutions to Try

### Solution 1: Check Current Driver Behavior

First, we need to see what happens when our driver loads:

```bash
# Clean rebuild
make clean && make

# Load and check detailed logs
sudo insmod gc2607.ko
sudo dmesg | grep -A50 "GC2607 probe started"
sudo dmesg | grep -i int3472

# Check if regulator user count increased
cat /sys/class/regulator/regulator.1/num_users

# Check I2C device creation
ls -la /sys/bus/i2c/devices/5-0037/

# Unload
sudo rmmod gc2607
```

### Solution 2: Add Regulator Consumer Mapping (if needed)

If the driver can't find the regulator automatically, we can add explicit mapping in the driver:

```c
// In gc2607_probe(), before devm_regulator_bulk_get():
static struct regulator_consumer_supply gc2607_consumer_supplies[] = {
    REGULATOR_SUPPLY("avdd", "i2c-GCTI2607:00"),
};

// Or use regulator_register_supply_alias()
```

### Solution 3: Check ACPI GPIO Resources

Extract ACPI tables to see GPIO resource declarations:

```bash
# Install ACPI tools (if not installed)
sudo pacman -S acpica

# Extract and decompile DSDT
sudo acpidump -b
sudo iasl -d dsdt.dat

# Search for GCTI2607 device definition
grep -A100 "Device.*GCTI2607\|LNK0" dsdt.dsl
```

Look for:
- `GpioIo` or `GpioInt` resources
- `_CRS` (Current Resource Settings)
- `_DEP` (Dependencies) pointing to INT3472:01

### Solution 4: Add GPIO Lookup Table

If GPIOs exist but aren't named correctly, add a lookup table:

```c
#include <linux/gpio/machine.h>

static struct gpiod_lookup_table gc2607_gpios = {
    .dev_id = "i2c-GCTI2607:00",
    .table = {
        GPIO_LOOKUP_IDX("INT3472:01", 0, "reset", 0, GPIO_ACTIVE_LOW),
        GPIO_LOOKUP_IDX("INT3472:01", 1, "powerdown", 0, GPIO_ACTIVE_HIGH),
        { }
    },
};

// In module_init:
gpiod_add_lookup_table(&gc2607_gpios);

// In module_exit:
gpiod_remove_lookup_table(&gc2607_gpios);
```

### Solution 5: Manual Power Control

As a last resort, if INT3472 manages power internally through ACPI methods:

```c
// Call ACPI power management methods directly
acpi_status status;
status = acpi_evaluate_object(ACPI_HANDLE(&client->dev), "_PS0", NULL, NULL);
```

## Next Steps

### Step 1: Test Current Driver (REQUIRED)
Run the current driver and collect full logs to see exactly what's happening:

```bash
sudo insmod gc2607.ko
sudo dmesg | tail -100 > gc2607_probe_log.txt
cat /sys/class/regulator/regulator.1/num_users
ls -la /sys/bus/i2c/devices/5-0037/
sudo rmmod gc2607
```

**Please run this and share the output!**

### Step 2: Extract ACPI Tables
Get the ACPI DSDT to see the exact GPIO/power relationships:

```bash
chmod +x extract_acpi.sh
./extract_acpi.sh
```

### Step 3: Try I2C Communication Test
Even without power control working, try to see if the sensor responds:

```bash
# Check if device responds (requires sudo)
sudo i2cdetect -y 5

# If 0x37 shows as "37" (not UU), try reading chip ID directly
sudo i2cget -y 5 0x37 0x03f0 w
```

## Expected Outcomes

### Best Case
- Driver loads successfully
- Resources are found through ACPI
- Chip ID detected: 0x2607
- **Action**: Move to Phase 3 (register initialization)

### Most Likely Case
- Driver loads but doesn't find all resources
- Sensor doesn't respond on I2C (error -121)
- **Action**: Add resource mappings based on ACPI analysis

### Worst Case
- ACPI doesn't declare GPIOs/resources at all
- INT3472 handles everything internally through ACPI methods
- **Action**: May need to reverse-engineer ACPI methods or use Windows driver behavior as reference

## Files Created for Debugging

1. `check_int3472.sh` - Check INT3472 PMIC status and bindings
2. `find_pmic_link.sh` - Identify which INT3472 belongs to GC2607
3. `analyze_int3472_gc2607.sh` - Analyze INT3472:01 resources for GC2607
4. `extract_acpi.sh` - Extract ACPI tables for analysis
5. This file - Comprehensive analysis

## References

- Linux kernel: `drivers/platform/x86/intel/int3472/discrete.c`
- Linux kernel: `drivers/media/i2c/ov01a10.c` (reference IPU6 sensor driver)
- ACPI specification for camera sensor integration
- Intel IPU6 documentation

## Summary

We've confirmed the hardware connection:
- **GC2607 sensor** (GCTI2607:00) on I2C bus 5, address 0x37
- **INT3472:01 PMIC** (DSC0) providing power and control
- **Resources exist** but need proper mapping

The next critical step is to **test the current driver** and see if it can communicate with the sensor, even without perfect power control. Share the logs and we can proceed with the appropriate fix.
