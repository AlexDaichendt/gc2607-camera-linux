# GC2607 Linux Camera Bring-Up

This repo documents and packages the patches/scripts needed to reproduce the working GC2607 camera
state on the MateBook host.

The working path is:

```text
GC2607 kernel driver, stable 1920x1080 raw
  -> Intel IPU6 HAL producer at 1920x1080
  -> HAL padding bridge to 1928x1088
  -> GC2607 Windows-derived graph + AIQB
  -> PSYS/AIQ ISP output as NV12 1920x1080
  -> optional v4l2loopback camera for Discord
```

## Repo Layout

```text
patches/driver/        Kernel driver patches for gc2607-v4l2-driver
patches/hal/           Intel IPU6 HAL source/XML patches
scripts/               Runtime and install helper scripts
systemd/user/          User service for the Discord virtual camera bridge
config/                v4l2loopback boot config examples
docs/                  Bring-up notes and private asset documentation
assets/private/        Local-only place for Windows-derived assets; ignored by git
```

## What Is Not Committed

The AIQB and Windows graph XML are required for the best-quality path, but they are not committed
here because they came from the Windows driver payload and may not be redistributable.

Expected private asset filenames:

```text
gc2607_gc2607_MTL.aiqb
graph_settings_gc2607_gc2607_MTL.xml
graph_descriptor.xml
```

See `docs/private-assets.md` for checksums from the working machine.

## Source Repos

Expected source locations on the host:

```sh
~/repos/gc2607-v4l2-driver
~/repos/ipu6-camera-hal-gc2607
```

## Apply Driver Patch

```sh
cd ~/repos/gc2607-v4l2-driver
git apply ~/repos/gc2607-camera-linux-bringup/patches/driver/0001-gc2607-controls-timing-for-ipu6.patch
make
```

The driver patch keeps the sensor on the stable `1920x1080` mode and adds the controls/timing the
IPU6 HAL needs.

## Apply HAL Patches

```sh
cd ~/repos/ipu6-camera-hal-gc2607
git apply ~/repos/gc2607-camera-linux-bringup/patches/hal/0001-gc2607-profile-and-psys-padding.patch
git apply ~/repos/gc2607-camera-linux-bringup/patches/hal/0002-add-gc2607-sensor-xml.patch
```

Then install the private Windows-derived assets into the HAL tree:

```sh
~/repos/gc2607-camera-linux-bringup/scripts/install-private-hal-assets.sh \
  ~/repos/ipu6-camera-hal-gc2607 \
  ~/repos/gc2607-camera-linux-bringup/assets/private
```

Build and install the HAL prefix:

```sh
cd ~/repos/ipu6-camera-hal-gc2607
cmake --build build-gc2607 -j"$(nproc)"
cmake --install build-gc2607 --prefix "$HOME/opt/gc2607-ipu6"
```

## Verify HAL Output

```sh
systemctl --user stop wireplumber.service 2>/dev/null || true
PREFIX="$HOME/opt/gc2607-ipu6"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0"
export GST_REGISTRY="$PREFIX/gstreamer-registry.bin"

timeout 20s gst-launch-1.0 -e -q \
  icamerasrc device-name=gc2607-uf num-buffers=120 \
  ! "video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1" \
  ! fakesink sync=false
```

Expected result: exit code `0`.

## Discord Virtual Camera

Discord sees the raw IPU6 V4L2 nodes as `ipu6`, but those are not usable webcam outputs. Use a
virtual webcam fed by the HAL pipeline.

One-time loopback setup:

```sh
sudo cp ~/repos/gc2607-camera-linux-bringup/config/modprobe.d/gc2607-loopback.conf /etc/modprobe.d/
sudo cp ~/repos/gc2607-camera-linux-bringup/config/modules-load.d/gc2607-loopback.conf /etc/modules-load.d/
sudo modprobe v4l2loopback
```

Install the user service:

```sh
~/repos/gc2607-camera-linux-bringup/scripts/install-discord-service.sh
```

Start only when needed to save battery:

```sh
systemctl --user start gc2607-discord-camera.service
```

Stop after calls:

```sh
systemctl --user stop gc2607-discord-camera.service
```

Select this camera in Discord:

```text
GC2607 HAL Camera
```

## Power Notes

The GStreamer bridge keeps the sensor, IPU6 pipeline, and conversion path active. It is appropriate
to run during calls, but should not be left running all day on battery.

The v4l2loopback module itself is cheap when idle; the expensive part is the running
`gc2607-discord-camera.service`.

## Upstream Notes

The current HAL padding bridge is deliberately narrow and hard-coded for GC2607:

```text
1920x1080 SGRBG10 -> 1928x1088 SGRBG10
left pad = 4 pixels
top pad = 4 rows
```

For upstream, this should probably become a data-driven raw-input padding quirk rather than a
GC2607-specific block inside `PSysProcessor`.

The AIQB/graph redistribution question must be resolved before trying to upstream the full HAL
configuration.
