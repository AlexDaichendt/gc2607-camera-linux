# GC2607 Linux Camera Bring-Up

This repo documents the Linux bring-up path for the GalaxyCore GC2607 camera on Intel IPU6
systems. It contains the kernel-driver patch, Intel IPU6 HAL patch, GC2607 HAL assets, and
scripts needed to build the driver stack and verify processed camera output with GStreamer.

The validated pipeline is:

```text
GC2607 sensor
  -> patched GC2607 V4L2 subdevice driver
  -> Intel IPU6 ISYS raw capture at 1920x1080 SGRBG10
  -> Intel IPU6 HAL/PSYS with GC2607 AIQB and graph XML
  -> processed NV12 1920x1080 frames from icamerasrc
  -> gst-launch frame capture
```

The checkpoint here is the kernel and HAL stack plus a known-good GStreamer validation path.

## Credits

This work builds on the initial GC2607 Linux V4L2 driver project:

```text
https://github.com/abbood/gc2607-v4l2-driver
```

That project did the early sensor-driver bring-up, including ACPI binding, INT3472 power/reset
handling, V4L2 subdevice support, IPU6 media-controller integration, and raw Bayer capture. This
repo packages the later driver/HAL changes and GC2607 HAL assets needed for processed IPU6 output.

See `CREDITS.md` for more detail.

## Hardware Scope

Validated hardware:

```text
sensor: GalaxyCore GC2607
ACPI HID: GCTI2607
platform: Intel IPU6 / Meteor Lake class laptop
raw mode: SGRBG10_1X10 1920x1080
HAL output: NV12 1920x1080 @ 30 fps
```

The tested system exposes the sensor as `i2c-GCTI2607:00`.

## Repo Layout

```text
assets/hal/       GC2607 AIQB and graph XML used by the HAL pipeline
config/           boot-time module and udev configuration
docs/             asset checksums, raw capture, and troubleshooting notes
patches/driver/   patch for the GC2607 V4L2 driver
patches/hal/      patches for Intel ipu6-camera-hal
patches/ipu6-drivers/
                  patch for the older out-of-tree IPU bridge table
scripts/          clone, patch, install, and validation scripts
third_party/      upstream source repos tracked as git submodules
```

## Required Sources

Clone this repo with its third-party source submodules:

```sh
git clone --recurse-submodules https://github.com/AlexDaichendt/gc2607-camera-linux
cd gc2607-camera-linux
```

If this repo is already checked out, initialize or refresh the source submodules:

```sh
git submodule update --init --recursive
```

The examples below assume:

```sh
export BRINGUP="$PWD"
export DRIVER="$BRINGUP/third_party/gc2607-v4l2-driver"
export HAL="$BRINGUP/third_party/ipu6-camera-hal"
export IPU6_DRIVERS="$BRINGUP/third_party/ipu6-drivers"
```

## Dependencies

Arch/CachyOS-style package names:

```sh
sudo pacman -S --needed \
  base-devel git cmake ninja dkms linux-headers \
  v4l-utils media-ctl \
  gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad
```

The Intel HAL also needs Intel's IPU6 userspace dependencies and camera binaries. Use the current
Intel instructions for:

```text
https://github.com/intel/ipu6-camera-hal
https://github.com/intel/ipu6-camera-bins
https://github.com/intel/icamerasrc/tree/icamerasrc_slim_api
```

## Apply Patches And HAL Assets

Automatic:

```sh
"$BRINGUP/scripts/apply-patches.sh"
```

Manual equivalent:

```sh
cd "$DRIVER"
git apply "$BRINGUP/patches/driver/0001-gc2607-controls-timing-for-ipu6.patch"

cd "$HAL"
git apply "$BRINGUP/patches/hal/0001-gc2607-profile-and-psys-padding.patch"
git apply "$BRINGUP/patches/hal/0002-add-gc2607-sensor-xml.patch"
"$BRINGUP/scripts/install-hal-assets.sh" "$HAL"

cd "$IPU6_DRIVERS"
git apply "$BRINGUP/patches/ipu6-drivers/0001-cio2-bridge-add-gc2607-sensor.patch"
```

Included HAL assets:

```text
assets/hal/gc2607_gc2607_MTL.aiqb
assets/hal/graph_settings_gc2607_gc2607_MTL.xml
assets/hal/graph_descriptor.xml
```

See `docs/assets.md` for checksums and asset notes.

## Build And Install Kernel Modules

Build and install the GC2607 sensor module with DKMS:

```sh
sudo DRIVER="$DRIVER" "$BRINGUP/scripts/install-gc2607-dkms.sh"
```

Install Intel IPU6 PSYS support with DKMS:

```sh
IPU6_DRIVERS="$IPU6_DRIVERS" "$BRINGUP/scripts/install-ipu6-psys-dkms.sh"
```

The GC2607 also needs an IPU bridge sensor-table entry for ACPI HID `GCTI2607`
with link frequency `336000000`. The included `ipu6-drivers` patch covers older
out-of-tree bridge builds. On current kernels where `modinfo ipu-bridge` points
at the distro kernel module, rebuild or override that kernel module with the
same entry. See `docs/ipu-bridge.md`.

Install boot-time module loading and `/dev/ipu-psys0` permissions:

```sh
"$BRINGUP/scripts/install-system-config.sh"
```

Expected kernel state:

```sh
dkms status -m gc2607
dkms status -m ipu6-drivers
lsmod | rg "^(gc2607|intel_ipu6|intel_ipu6_isys|intel_ipu6_psys)\b"
find /sys/bus/i2c/drivers/gc2607 -maxdepth 1 -mindepth 1 -printf "%f\n"
ls -l /dev/ipu-psys0
```

Expected GC2607 bind target:

```text
i2c-GCTI2607:00
```

## Build And Install The HAL

Configure and install the patched HAL into a prefix:

```sh
cd "$HAL"

cmake -S . -B build-gc2607 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/opt/gc2607-ipu6"

cmake --build build-gc2607 -j"$(nproc)"
cmake --install build-gc2607
```

Use whatever additional CMake options Intel's current HAL documentation requires for your distro.

## Validate With GStreamer

Set up the HAL runtime environment:

```sh
export GC2607_PREFIX="$HOME/opt/gc2607-ipu6"
export LD_LIBRARY_PATH="$GC2607_PREFIX/lib:$GC2607_PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$GC2607_PREFIX/lib/gstreamer-1.0"
export GST_REGISTRY="$GC2607_PREFIX/gstreamer-registry.bin"
```

Smoke-test streaming:

```sh
"$BRINGUP/scripts/verify-hal.sh"
```

Capture JPEG frames:

```sh
"$BRINGUP/scripts/capture-gst-frame.sh" /tmp/gc2607-frame
```

That writes a short frame sequence such as:

```text
/tmp/gc2607-frame-00.jpg
/tmp/gc2607-frame-01.jpg
...
```

The GStreamer source is:

```sh
icamerasrc device-name=gc2607-uf
```

The expected negotiated stream is:

```text
video/x-raw, format=NV12, width=1920, height=1080, framerate=30/1
```

On the validated laptop the sensor is physically mounted inverted, so the capture script applies
`videoflip method=rotate-180` after HAL processing. Override with `GC2607_FLIP_METHOD=identity` if
your hardware does not need that correction.

## Use As An On-Demand Virtual Webcam

For compatibility with Discord, Telegram, and browser WebRTC camera pickers, use the GStreamer HAL
output as a `v4l2loopback` virtual webcam:

```sh
"$BRINGUP/scripts/install-virtual-camera-desktop.sh"
"$BRINGUP/scripts/virtual-camera.sh" prepare
"$BRINGUP/scripts/virtual-camera.sh" start
```

Select `GC2607 Virtual Camera` in the application, then stop the real camera pipeline when done:

```sh
"$BRINGUP/scripts/virtual-camera.sh" stop
```

`install-virtual-camera-desktop.sh` hides the raw IPU6 and uncalibrated libcamera GC2607 sources
from WirePlumber. `prepare` creates the cheap virtual V4L2 device and registers it with PipeWire
without opening the real camera. `start` arms an on-demand watcher: it keeps a black standby stream
attached so WebRTC camera pickers can see `/dev/video60`, then swaps in the real `icamerasrc`
feeder only while an app actually opens `GC2607 Virtual Camera`. The script is deliberately not
installed as an autostart service, so messaging apps can remain open without keeping the camera
active.

See `docs/virtual-camera.md` for status, logs, output-mode overrides, and unloading the loopback
device.

## Runtime Checks

Use:

```sh
"$BRINGUP/scripts/check-runtime.sh"
```

For lower-level raw capture checks, see `docs/direct-raw.md`.
