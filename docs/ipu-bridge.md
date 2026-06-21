# IPU Bridge GC2607 Entry

The IPU bridge creates the software-node camera graph that lets IPU6 ISYS connect an ACPI-enumerated
sensor to the CSI-2 receiver. For this GC2607 laptop, the bridge must know the sensor ACPI HID and
link frequency:

```c
IPU_SENSOR_CONFIG("GCTI2607", 1, 336000000),
```

`GCTI2607` is the ACPI HID exposed by the firmware, `1` is the number of link frequencies, and
`336000000` is the 336 MHz link frequency used by the GC2607 driver patch.

## Which Source Needs The Entry?

There are two cases:

```text
Older / out-of-tree IPU6 builds:
  third_party/ipu6-drivers/drivers/media/pci/intel/cio2-bridge.c
  macro: CIO2_SENSOR_CONFIG("GCTI2607", 1, 336000000)

Current distro kernels:
  kernel source drivers/media/pci/intel/ipu-bridge.c
  macro: IPU_SENSOR_CONFIG("GCTI2607", 1, 336000000)
```

On the validated CachyOS machine, `modinfo ipu-bridge` reports:

```text
/lib/modules/7.0.12-1-cachyos/kernel/drivers/media/pci/intel/ipu-bridge.ko.zst
```

That means the running bridge is supplied by the distro kernel, not by the `ipu6-drivers` DKMS tree.
The `ipu6-drivers` submodule still matters for PSYS on this setup, but rebuilding that DKMS package
will not replace the running `ipu-bridge` module on current kernels.

## Submodule Patch

For older kernels where `ipu6-drivers` builds the bridge, apply the repo patches:

```sh
"$BRINGUP/scripts/apply-patches.sh"
```

or manually:

```sh
cd "$IPU6_DRIVERS"
git apply "$BRINGUP/patches/ipu6-drivers/0001-cio2-bridge-add-gc2607-sensor.patch"
```

This adds:

```c
/* GalaxyCore GC2607 */
CIO2_SENSOR_CONFIG("GCTI2607", 1, 336000000),
```

to `drivers/media/pci/intel/cio2-bridge.c`.

## Distro Kernel Patch

For current kernels that ship `ipu-bridge`, patch the matching kernel source instead:

```text
drivers/media/pci/intel/ipu-bridge.c
```

Add this entry to the bridge sensor table:

```c
/* GalaxyCore GC2607 */
IPU_SENSOR_CONFIG("GCTI2607", 1, 336000000),
```

Then rebuild and install that kernel module using the distro's normal kernel packaging flow, or build
a local override module for the exact `uname -r`. The module must match the running kernel vermagic.

The old helper scripts in `third_party/gc2607-v4l2-driver` are useful as historical notes, but they
are hardcoded for an older Arch kernel. Do not run them directly on a different kernel release.

## Check The Running Module

Confirm which bridge module is loaded from disk:

```sh
modinfo ipu-bridge | rg 'filename|vermagic'
```

Check whether a compressed installed module already contains the GC2607 HID:

```sh
zstd -d -c /lib/modules/"$(uname -r)"/kernel/drivers/media/pci/intel/ipu-bridge.ko.zst \
  | strings | rg GCTI2607
```

If your kernel installs an uncompressed module, use:

```sh
strings /lib/modules/"$(uname -r)"/kernel/drivers/media/pci/intel/ipu-bridge.ko | rg GCTI2607
```

After booting with the patched bridge, the media graph should expose the GC2607 sensor and IPU6
entities:

```sh
media-ctl --print-topology | rg -i 'gc2607|ipu6|GCTI2607'
```
