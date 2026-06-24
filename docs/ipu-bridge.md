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

## Auto-Rebuild On Kernel Upgrade (Arch)

The stock in-tree `ipu-bridge` lacks the `GCTI2607` entry, so **every kernel upgrade replaces the
running bridge with one that does not know about the GC2607 and the camera silently stops working**
until the override is rebuilt. The DKMS sensor module rebuilds itself on upgrade, but the bridge
override does not — it is not a DKMS package.

To rebuild the override automatically, install the pacman hook:

```sh
scripts/install-ipu-bridge-hook.sh
```

This installs:

```text
/usr/local/lib/gc2607/rebuild-ipu-bridge-override.sh   rebuild logic
/usr/local/lib/gc2607/ipu-bridge.c                     vendored fallback source
/etc/pacman.d/hooks/90-gc2607-ipu-bridge.hook          PostTransaction trigger
```

On every kernel install/upgrade, the hook runs `rebuild-ipu-bridge-override.sh --pacman-targets`,
which for each updated kernel:

1. skips if a current override is already installed (`GCTI2607` present and vermagic matches);
2. otherwise compiles `bridge/ipu-bridge.c` (vendored, with the `GCTI2607` entry inserted
   idempotently) against that kernel's `build/` headers;
3. if the vendored source does not match a newer kernel's bridge ABI, fetches the matching-version
   `ipu-bridge.c` from `git.kernel.org` and retries;
4. signs the module with the DKMS MOK (if present) and installs it to
   `/lib/modules/<kver>/updates/ipu-bridge.ko`, then runs `depmod`.

The rebuild requires that kernel's `linux-headers` to be installed; if they are missing the hook
prints a warning and skips that kernel. You can also rebuild manually at any time:

```sh
sudo scripts/rebuild-ipu-bridge-override.sh            # current kernel
sudo scripts/rebuild-ipu-bridge-override.sh 7.0.11-arch1-1
```

> Note: the override stages in `updates/`. A reboot brings up the new bridge and sensor in the
> correct order; the camera may not bind until then.

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
