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
