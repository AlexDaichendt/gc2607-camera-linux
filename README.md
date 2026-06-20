# GC2607 Linux Camera Bring-Up

This repo is a complete bring-up kit for the GalaxyCore GC2607 camera on Intel IPU6 systems. It
packages the driver/HAL patches, GC2607 HAL assets, validation commands, and Discord virtual-camera
service used to get the camera working as a normal webcam.

The working path is:

```text
GC2607 sensor driver, stable 1920x1080 raw
  -> Intel IPU6 ISYS producer at 1920x1080
  -> HAL padding bridge to the graph's 1928x1088 input
  -> GC2607 AIQB + graph XML
  -> IPU6 PSYS/AIQ ISP output as NV12 1920x1080
  -> optional v4l2loopback webcam for Discord
```

## Credits

This work builds on the initial GC2607 Linux V4L2 driver project:

```text
https://github.com/abbood/gc2607-v4l2-driver
```

That repo did the early sensor-driver bring-up: ACPI binding, INT3472 power/reset handling, V4L2
subdevice support, IPU6 media-controller integration, and raw Bayer capture. This repo adds the
current IPU6 HAL/AIQB path and packaging needed for a processed webcam output.

See `CREDITS.md` for more detail.

## Hardware Scope

Known working hardware:

```text
sensor: GalaxyCore GC2607
ACPI HID: GCTI2607
platform: Intel IPU6 / Meteor Lake class laptop
tested output: 1920x1080 @ 30fps
raw format: SGRBG10 / BA10
```

This was validated on a Huawei MateBook-style system where the sensor appears as `i2c-GCTI2607:00`.

## Repo Layout

```text
assets/hal/            GC2607 AIQB and graph XML used by the HAL pipeline
patches/driver/        Patch for the GC2607 V4L2 driver
patches/hal/           Patches for Intel ipu6-camera-hal
scripts/               Clone/apply/build/runtime helper scripts
systemd/user/          User service for the Discord virtual camera bridge
config/                v4l2loopback boot config examples
docs/                  Bring-up notes, raw capture, assets, troubleshooting
```

## Required Upstream Sources

Use a neutral workspace. The rest of this README assumes these variables:

```sh
export WORKDIR="$HOME/src/gc2607-camera"
export BRINGUP="$WORKDIR/gc2607-camera-linux-bringup"
export DRIVER="$WORKDIR/gc2607-v4l2-driver"
export HAL="$WORKDIR/ipu6-camera-hal"
export IPU6_DRIVERS="$WORKDIR/ipu6-drivers"
```

Clone the upstream sources:

```sh
mkdir -p "$WORKDIR"
cd "$WORKDIR"

git clone https://github.com/abbood/gc2607-v4l2-driver.git
git clone https://github.com/intel/ipu6-camera-hal.git
git clone https://github.com/intel/ipu6-drivers.git

# Replace this placeholder with this repo's real URL when it is published.
git clone <gc2607-camera-linux-bringup-url> gc2607-camera-linux-bringup
```

If you already have this repo checked out, you can clone only the source repos:

```sh
"$BRINGUP/scripts/clone-sources.sh" "$WORKDIR"
```

## Dependencies

Arch/CachyOS-style package names:

```sh
sudo pacman -S --needed \
  base-devel git cmake ninja linux-headers \
  v4l-utils media-ctl \
  gstreamer gst-plugins-base gst-plugins-good \
  v4l2loopback-dkms
```

The Intel HAL also depends on Intel's IPU6 userspace stack and binaries. Follow the current Intel
instructions for:

```text
https://github.com/intel/ipu6-camera-hal
https://github.com/intel/ipu6-camera-bins
https://github.com/intel/icamerasrc/tree/icamerasrc_slim_api
```

The working system already had `icamerasrc`, HAL dependencies, and IPU6 camera binaries installed.

## Apply Patches And Assets

Automatic:

```sh
"$BRINGUP/scripts/apply-patches.sh" "$WORKDIR"
```

Manual equivalent:

```sh
cd "$DRIVER"
git apply "$BRINGUP/patches/driver/0001-gc2607-controls-timing-for-ipu6.patch"

cd "$HAL"
git apply "$BRINGUP/patches/hal/0001-gc2607-profile-and-psys-padding.patch"
git apply "$BRINGUP/patches/hal/0002-add-gc2607-sensor-xml.patch"
"$BRINGUP/scripts/install-hal-assets.sh" "$HAL"
```

The included HAL assets are:

```text
assets/hal/gc2607_gc2607_MTL.aiqb
assets/hal/graph_settings_gc2607_gc2607_MTL.xml
assets/hal/graph_descriptor.xml
```

See `docs/assets.md` for checksums.

## Build The GC2607 Driver

```sh
cd "$DRIVER"
make
```

The driver patch:

- keeps the stable Linux raw mode at `1920x1080`
- adds `HBLANK` and `VBLANK` controls
- updates VTS through sensor registers `0x0220/0x0221`
- exposes analogue gain on a 64-based scale
- accepts digital gain as a no-op for HAL control compatibility
- supports Clang/LLVM kernel builds such as CachyOS

## Load The Driver For Testing

Stop desktop camera users while testing:

```sh
systemctl --user stop wireplumber.service 2>/dev/null || true
```

Load required modules and the out-of-tree driver:

```sh
sudo modprobe videodev
sudo modprobe ipu_bridge
sudo modprobe intel_ipu6
sudo modprobe intel_ipu6_isys

cd "$DRIVER"
sudo insmod ./gc2607.ko
```

If the module is already loaded:

```sh
echo i2c-GCTI2607:00 | sudo tee /sys/bus/i2c/drivers/gc2607/unbind
sudo rmmod gc2607
sudo insmod "$DRIVER/gc2607.ko"
```

Check detection:

```sh
media-ctl -d /dev/media0 --print-topology | rg -n "gc2607|GCTI2607|CSI2|Capture"
```

## Direct Raw Sanity Test

Direct raw capture confirms that the sensor driver and ISYS path work. It is not the final webcam
path.

```sh
media-ctl -d /dev/media0 -l '"gc2607 5-0037":0 -> "Intel IPU6 CSI2 0":0 [1]' 2>&1 || true
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0 [1]' 2>&1 || true

media-ctl -d /dev/media0 -V '"gc2607 5-0037":0 [fmt:SGRBG10_1X10/1920x1080]' 2>&1 || true
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":0 [fmt:SGRBG10_1X10/1920x1080]'
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":1 [fmt:SGRBG10_1X10/1920x1080]'

v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
timeout 8s v4l2-ctl -d /dev/video0 --stream-mmap=4 --stream-count=2 --stream-to=/tmp/gc2607_raw.bin
```

Expected mode:

```text
BA10 / SGRBG10
1920x1080
bytesperline 3840
```

See `docs/direct-raw.md` for more raw-capture notes.

## IPU6 PSYS Support

The HAL path needs `/dev/ipu-psys0`.

Check it:

```sh
ls -l /dev/ipu-psys0
```

If it is missing, build/load PSYS support from Intel's driver repo:

```sh
cd "$IPU6_DRIVERS"
```

Use the build instructions from `https://github.com/intel/ipu6-drivers` for your kernel. On the
working host, `intel-ipu6-psys.ko` was built from that repo and `/dev/ipu-psys0` appeared with
`root:video` permissions.

## Build And Install The HAL

The exact configure command depends on distro packaging and where Intel IPU6 binaries are installed.
The working machine used a configured build directory named `build-gc2607`.

If you already have a configured build directory:

```sh
cd "$HAL"
cmake --build build-gc2607 -j"$(nproc)"
cmake --install build-gc2607 --prefix "$HOME/opt/gc2607-ipu6"
```

If starting from a fresh HAL clone, follow Intel's `ipu6-camera-hal` build instructions first, then
apply the patches/assets above and install to the prefix you want to test.

## Verify Processed HAL Output

```sh
"$BRINGUP/scripts/verify-hal.sh"
```

Manual equivalent:

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

Expected result:

```text
exit code 0
120 frames returned
```

Working HAL log signatures:

```text
Producer config for port:0, fmt:GRBG10 (1920x1080), needProcessor=1
Enable GC2607 PSYS raw padding on port:0 (1920x1080 -> 1928x1088)
isSameStreamConfig ... GRBG10(1928x1088: 3904)
padGc2607InputBuffers ... 1920x1080/3840 -> 1928x1088/3904
frame returned
```

## Discord / Normal Webcam Apps

Discord sees raw `ipu6` nodes, but those are not usable webcam outputs. Use the HAL pipeline through
`v4l2loopback`.

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

Start the camera for calls:

```sh
systemctl --user start gc2607-discord-camera.service
```

Stop it after calls to save battery:

```sh
systemctl --user stop gc2607-discord-camera.service
```

Select this camera in Discord:

```text
GC2607 HAL Camera
```

The bridge defaults to `1280x720`, `30fps`, and `rotate-180` because the tested laptop's camera image
was upside down before rotation.

## Troubleshooting

See `docs/troubleshooting.md`.

Common quick checks:

```sh
"$BRINGUP/scripts/check-runtime.sh"
systemctl --user status gc2607-discord-camera.service --no-pager
sudo fuser -v /dev/video* /dev/v4l-subdev* /dev/media*
```

## Upstream Notes

The driver patch is the easiest part to upstream back to the GC2607 driver repo.

The HAL patch works, but it currently contains a GC2607-specific padding bridge in `PSysProcessor`.
For upstreaming to Intel's HAL, this should probably become a data-driven raw-input padding quirk
configured from sensor/platform XML rather than hard-coded for one sensor.

The included AIQB/graph assets came from the Windows driver payload used during bring-up. Verify
redistribution terms before publishing this repo publicly.
