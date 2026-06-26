# Hardware Detection Results

## ACPI Status
```bash
$ cat /sys/bus/acpi/devices/GCTI2607*/status
15  # ENABLED
```

## I2C Device
```bash
$ cat /sys/devices/.../i2c-5/i2c-GCTI2607:00/modalias
acpi:GCTI2607:GCTI2607:

$ cat .../i2c-GCTI2607:00/name  
GCTI2607:00
```

## PMIC
```bash
$ lsmod | grep int3472
intel_skl_int3472_discrete    28672  0
intel_skl_int3472_common      16384  2
```

Privacy LED brightness: 0 (camera unpowered, waiting for driver)
