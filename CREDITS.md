# Credits

This bring-up repo builds on the initial GC2607 Linux V4L2 driver work from:

```text
https://github.com/abbood/gc2607-v4l2-driver
```

That project did the important early work of bringing up the GalaxyCore GC2607 sensor as an
out-of-tree Linux V4L2 subdevice driver, including ACPI binding, INT3472 power/reset handling,
MIPI/IPU6 media-controller integration, raw Bayer capture, and early application-facing virtual
camera scripts.

This repo adds the later IPU6 HAL/AIQ path:

- GC2607 AIQB and graph assets
- Intel IPU6 HAL sensor XML
- a PSYS raw-padding bridge for the `1920x1080` Linux sensor mode to the `1928x1088` graph input
- current driver timing/control fixes needed by the HAL
- Discord-oriented v4l2loopback service scripts

Intel IPU6 userspace/kernel source references:

```text
https://github.com/intel/ipu6-camera-hal
https://github.com/intel/ipu6-drivers
```

The GC2607 AIQB/graph assets included in `assets/hal/` came from the Windows driver payload used
during local bring-up. Verify redistribution terms before publishing this repo publicly.
