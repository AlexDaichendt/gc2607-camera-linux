# GC2607 Linux Camera Bring-Up

This repo packages the patches, HAL assets, and runtime scripts needed to reproduce the working
GC2607 camera state on Linux.

The working path is:

```text
GC2607 kernel driver, stable 1920x1080 raw
  -> Intel IPU6 HAL producer at 1920x1080
  -> HAL padding bridge to 1928x1088
  -> GC2607 graph + AIQB
  -> PSYS/AIQ ISP output as NV12 1920x1080
  -> optional v4l2loopback camera for Discord
```

## Repo Layout

```text
assets/hal/            GC2607 AIQB and graph XML used by the working HAL pipeline
patches/driver/        Kernel driver patches for gc2607-v4l2-driver
patches/hal/           Intel IPU6 HAL source/XML patches
scripts/               Runtime and install helper scripts
systemd/user/          User service for the Discord virtual camera bridge
config/                v4l2loopback boot config examples
docs/                  Bring-up notes and asset checksums
```

## Clone The Required Repos

Pick a workspace directory and clone this bring-up repo plus the upstream sources:

```sh
export WORKDIR="$HOME/src/gc2607-camera"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

git clone https://github.com/abbood/gc2607-v4l2-driver.git
git clone https://github.com/intel/ipu6-camera-hal.git
git clone https://github.com/intel/ipu6-drivers.git

# If you are reading this from a local checkout, copy or clone this repo here too.
# Replace the URL with your published fork/remote when available.
git clone <gc2607-camera-linux-bringup-url> gc2607-camera-linux-bringup
```

The commands below assume those paths:

```sh
export BRINGUP="$WORKDIR/gc2607-camera-linux-bringup"
export DRIVER="$WORKDIR/gc2607-v4l2-driver"
export HAL="$WORKDIR/ipu6-camera-hal"
export IPU6_DRIVERS="$WORKDIR/ipu6-drivers"
```

## Apply Driver Patch

```sh
cd "$DRIVER"
git apply "$BRINGUP/patches/driver/0001-gc2607-controls-timing-for-ipu6.patch"
make
```

The driver patch keeps the sensor on the stable `1920x1080` mode and adds the controls/timing the
IPU6 HAL needs.

## Apply HAL Patches And Assets

```sh
cd "$HAL"
git apply "$BRINGUP/patches/hal/0001-gc2607-profile-and-psys-padding.patch"
git apply "$BRINGUP/patches/hal/0002-add-gc2607-sensor-xml.patch"

"$BRINGUP/scripts/install-hal-assets.sh" "$HAL"
```

Build and install the HAL prefix. The exact CMake configure command depends on the distro and any
existing local packaging, but the working host used a build directory named `build-gc2607`:

```sh
cd "$HAL"
cmake --build build-gc2607 -j"$(nproc)"
cmake --install build-gc2607 --prefix "$HOME/opt/gc2607-ipu6"
```

## PSYS Driver Support

The HAL path needs `/dev/ipu-psys0`. If your distro kernel does not already provide the IPU6 PSYS
driver, build/install it from:

```sh
cd "$IPU6_DRIVERS"
```

Use the build instructions from Intel's `ipu6-drivers` repo for your kernel. On the working host,
the PSYS module was built from that repo and `intel-ipu6-psys.ko` was loaded successfully.

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
sudo cp "$BRINGUP/config/modprobe.d/gc2607-loopback.conf" /etc/modprobe.d/
sudo cp "$BRINGUP/config/modules-load.d/gc2607-loopback.conf" /etc/modules-load.d/
sudo modprobe v4l2loopback
```

Install the user service:

```sh
"$BRINGUP/scripts/install-discord-service.sh"
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
