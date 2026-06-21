# Credits

This bring-up repo builds on the initial GC2607 Linux V4L2 driver work from:

```text
https://github.com/abbood/gc2607-v4l2-driver
```

That project did the important early work of bringing up the GalaxyCore GC2607 sensor as an
out-of-tree Linux V4L2 subdevice driver, including ACPI binding, INT3472 power/reset handling,
MIPI/IPU6 media-controller integration, raw Bayer capture, and sensor control plumbing.

This repo adds the IPU6 HAL/AIQ bring-up pieces:

- GC2607 AIQB and graph assets
- Intel IPU6 HAL sensor XML
- PSYS raw-padding support for the `1920x1080` Linux sensor mode and the HAL graph input
- driver timing/control fixes needed by the HAL
- DKMS and validation scripts for the kernel/HAL path

Intel IPU6 source references:

```text
https://github.com/intel/ipu6-camera-hal
https://github.com/intel/ipu6-drivers
```

The GC2607 AIQB/graph assets included in `assets/hal/` came from the Windows driver payload used
during bring-up. Verify redistribution terms before publishing this repo publicly.
