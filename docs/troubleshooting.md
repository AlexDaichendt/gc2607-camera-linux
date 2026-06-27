# Troubleshooting

This repo stops at kernel/HAL/GStreamer validation. The expected processed-frame path is:

```text
gc2607 kernel driver -> Intel IPU6 ISYS -> Intel HAL/PSYS -> icamerasrc -> GStreamer sink
```

## GC2607 Driver Is Missing

Check DKMS and module loading:

```sh
dkms status -m gc2607
modinfo gc2607
lsmod | rg "^gc2607\b"
find /sys/bus/i2c/drivers/gc2607 -maxdepth 1 -mindepth 1 -printf "%f\n"
```

Expected bound device:

```text
i2c-GCTI2607:00
```

If missing, install the patched driver:

```sh
sudo DRIVER="$DRIVER" "$BRINGUP/scripts/install-gc2607-dkms.sh"
```

## PSYS Device Is Missing

The HAL path needs `/dev/ipu-psys0`.

Check:

```sh
lsmod | rg "intel_ipu6.*psys|intel_ipu6_psys"
ls -l /dev/ipu-psys0
```

Install PSYS support:

```sh
IPU6_DRIVERS="$IPU6_DRIVERS" "$BRINGUP/scripts/install-ipu6-psys-dkms.sh"
"$BRINGUP/scripts/install-system-config.sh"
```

Expected permissions:

```text
root video ... /dev/ipu-psys0
```

## HAL Assets Are Missing

Check installed GC2607 assets:

```sh
PREFIX="${GC2607_PREFIX:-$HOME/opt/gc2607-ipu6}"
find "$PREFIX/etc/camera" -iname "*gc2607*" -o -iname "graph_settings_gc2607*"
```

The HAL install should include:

```text
gc2607_gc2607_MTL.aiqb
graph_settings_gc2607_gc2607_MTL.xml
gc2607-uf.xml
```

Reinstall assets into the HAL checkout and rebuild/install the HAL:

```sh
"$BRINGUP/scripts/install-hal-assets.sh" "$HAL"
cd "$HAL"
cmake --build build-gc2607 -j"$(nproc)"
cmake --install build-gc2607
```

## icamerasrc Is Missing

Check:

```sh
gst-inspect-1.0 icamerasrc
```

If missing, install/build Intel's `icamerasrc` slim API plugin for your distro and make sure
`GST_PLUGIN_PATH` points at the HAL prefix:

```sh
export GC2607_PREFIX="$HOME/opt/gc2607-ipu6"
export GST_PLUGIN_PATH="$GC2607_PREFIX/lib/gstreamer-1.0"
export GST_REGISTRY="$GC2607_PREFIX/gstreamer-registry.bin"
```

## GStreamer Does Not Produce Frames

Run the HAL smoke test:

```sh
"$BRINGUP/scripts/verify-hal.sh"
```

For more logging:

```sh
export cameraDebug=0x2
GST_DEBUG=2 "$BRINGUP/scripts/verify-hal.sh"
```

Check kernel messages:

```sh
journalctl -k -b --no-pager | rg -i "gc2607|ipu6|isys|psys|stream"
```

The expected sensor activity includes stream-on and stream-off messages from the GC2607 driver.

## Captured JPEG Is Black Or Stale

Capture a short sequence instead of a single first frame:

```sh
"$BRINGUP/scripts/capture-gst-frame.sh" /tmp/gc2607-frame 30
```

Inspect the later frames in the sequence. The first few frames after stream start can be less useful
while exposure and processing settle.

## Captured JPEG Is Upside Down

The tested laptop needs a 180-degree display correction after HAL processing. The capture script
defaults to:

```sh
GC2607_FLIP_METHOD=rotate-180
```

Set `GC2607_FLIP_METHOD=identity` when running `scripts/capture-gst-frame.sh` if your panel mounts
the sensor in the opposite orientation.

## HAL Build Fails With -Werror On Newer Toolchains

On newer GCC/Clang releases the Intel `ipu6-camera-hal` tree fails to build because it
compiles with `-Werror` and the source trips newer warnings such as
`-Wunused-but-set-variable`, e.g.:

```text
error: variable 'i' set but not used [-Werror=unused-but-set-variable=]
```

`patches/hal/0003-relax-werror-for-newer-toolchains.patch` (applied by
`scripts/apply-patches.sh`) adds `-Wno-error` so warnings stay warnings. If you build the
HAL without that patch, pass the flag manually instead:

```sh
cmake -S . -B build-gc2607 -DCMAKE_CXX_FLAGS="-Wno-error" ...
```

## HAL Build Succeeds But Produces No Libraries

If `cmake --build build-gc2607` exits 0 but no `ipu6epmtl.so` / `libcamhal.so` are
produced, the IPU version was not selected. The HAL's library targets are created
inside a `foreach(IPU_VER ...)` loop in `CMakeLists.txt`, so with no `IPU_VER` the
build has nothing to do. Reconfigure with the target set:

```sh
cmake -S . -B build-gc2607 -DCMAKE_BUILD_TYPE=Release \
  -DIPU_VER=ipu6epmtl -DUSE_PG_LITE_PIPE=ON \
  -DBUILD_CAMHAL_PLUGIN=ON -DBUILD_CAMHAL_ADAPTOR=ON \
  -DCMAKE_INSTALL_PREFIX="$HOME/opt/gc2607-ipu6"
```

On CMake 4.x also add `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` so the old
`cmake_minimum_required` is accepted.

## HAL Link Fails With `cannot find -lia_*-ipu6epmtl`

The HAL links against the Intel imaging libraries by unversioned name (e.g.
`-lia_aiqb_parser-ipu6epmtl`). Some `ipu6-camera-bins` packages install only the
runtime `libia_*-ipu6epmtl.so.0` files and omit the unversioned `.so` development
symlinks, so the link step fails even though the libraries are present. Create the
missing symlinks (re-run after any `ipu6-camera-bins` package update, which can
remove them again):

```sh
sudo sh -c 'cd /usr/lib && for f in lib*-ipu6epmtl.so.0; do
    [ -e "${f%.0}" ] || ln -s "$f" "${f%.0}"
done && ldconfig'
```

Adjust the libdir if your distro installs the bins somewhere other than `/usr/lib`.

## GC2607 DKMS Build Complains About A Missing dkms.conf

The `dkms.conf` ships at the root of the `gc2607-kernel/` driver tree, alongside `gc2607.c` and the
`Makefile`. `scripts/install-gc2607-dkms.sh` symlinks that tree into `/usr/src/gc2607-<version>` and
runs `dkms add`/`dkms install`, so the version and toolchain flag (`LLVM=1` only on clang-built
kernels) are derived automatically. If the build can't find it, make sure you're pointing `DRIVER`
at a tree that contains `dkms.conf`.

## Raw Capture Works But HAL Does Not

If `docs/direct-raw.md` works but `icamerasrc` fails, focus on:

- installed HAL prefix and `LD_LIBRARY_PATH`
- installed `icamerasrc` plugin and `GST_PLUGIN_PATH`
- GC2607 AIQB/XML assets under the HAL prefix
- PSYS module availability and `/dev/ipu-psys0` permissions
- HAL patch application state

Use:

```sh
"$BRINGUP/scripts/check-runtime.sh"
```
