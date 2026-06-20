# GC2607 Camera Bring-Up Notes

Date: 2026-06-20
Host: `alex@10.0.0.114`

This is the historical bring-up log. Path variables such as `$WORKDIR`, `$BRINGUP`, `$DRIVER`,
`$HAL`, and `$IPU6_DRIVERS` refer to the clone-based workflow in the top-level `README.md`.

## Goal

Get the GC2607 laptop camera working with the highest practical image quality on Linux.

The starting point was that direct raw capture could produce an image, but it looked bad. Online
comments suggested the problem might be a missing Intel IPU6 AIQB tuning file for this sensor.

## Short Conclusion

The missing AIQB/graph assets were the real blocker for proper ISP output.

The best-quality path is:

1. Keep the GC2607 kernel sensor driver on the stable Linux `1920x1080` raw mode.
2. Use the GC2607 AIQB and graph XML recovered from the Windows driver payload.
3. Run the Intel IPU6 HAL/PSYS pipeline.
4. Add a narrow HAL bridge that pads the stable `1920x1080` raw frame into the graph's expected
   `1928x1088` raw input before PSYS.

This now produces coherent `NV12 1920x1080` frames through `icamerasrc`.

## Repositories

Driver repo:

```sh
$DRIVER
```

HAL repo:

```sh
$HAL
```

Installed test prefix:

```sh
~/opt/gc2607-ipu6
```

## Windows Driver Payload Findings

Two Windows driver files were downloaded into `~/Downloads`.

The useful assets recovered from that payload were:

```text
gc2607_gc2607_MTL.aiqb
graph_settings_gc2607_gc2607_MTL.xml
graph_descriptor.xml
```

These confirmed that the Windows/Intel tuning expects GC2607 on Meteor Lake with a `1928x1088`
raw sensor mode and crops horizontally to `1920`.

The active graph key used for `1920x1080` output is `8004`. Important graph details:

```xml
<sensor ... mode_id="Full">
  <port_0 format="BG10" width="1928" height="1088" />
</sensor>

<pxl_crop_bayer_a>
  <input width="1928" height="1088" top="0" left="4" bottom="0" right="4" />
  <output width="1920" height="1088" top="0" left="0" bottom="0" right="0" />
</pxl_crop_bayer_a>

<ofa_2_mp>
  <input width="1920" height="1088" top="4" left="0" bottom="4" right="0" />
  <output width="1920" height="1080" top="0" left="0" bottom="0" right="0" />
</ofa_2_mp>
```

That means the graph expects `1928x1088` raw, horizontally crops 4 pixels on each side, then later
crops vertically from `1088` to `1080`.

## Why Not Pure Software Conversion

Software conversion from raw Bayer to RGB/YUV is possible, and it was useful diagnostically, but it
is not the best-quality path.

A software path would have to replace the ISP functions normally provided by Intel IPU6 and AIQ:

- demosaic
- black-level correction
- lens/color/shading correction
- auto exposure
- auto white balance
- denoise
- color correction matrix and tone mapping

The AIQB/graph path uses the intended ISP tuning. That is the right path for image quality.

## Kernel Driver Work

Repo:

```sh
$DRIVER
```

Important source files changed:

```text
Makefile
gc2607.c
```

Current branch name observed:

```text
hal-1928x1088
```

Despite the branch name, the driver is currently intentionally using the stable Linux `1920x1080`
mode. A true `1928x1088` sensor mode was tested and produced CSI problems or zero-byte captures.

Driver changes made:

- kept the active raw mode at `1920x1080`
- added/cleaned timing controls needed by the Intel HAL:
  - `V4L2_CID_HBLANK`
  - `V4L2_CID_VBLANK`
- wired VBLANK writes to sensor registers:
  - `0x0220`
  - `0x0221`
- restored sane `30 fps` timing:
  - `HTS = 2048`
  - `VTS = 0x0537` / `1335`
  - pixel rate derived from `2048 * 1335 * 30`
- changed analogue gain control to expose a 64-based ABI expected by local tests/HAL-style users
  and map that onto the sensor's 17-entry gain LUT
- exposed digital gain as an accepted no-op so HAL control updates do not fail
- added LLVM/Clang kernel-build detection in `Makefile` for CachyOS-style kernels

Kernel build artifacts are present in the repo and make `git status` noisy. These should not be
included in an upstream patch:

```text
*.o
*.ko
*.cmd
*.mod.c
Module.symvers
```

There are also diagnostic raw/png files in the driver repo. Those are test artifacts, not source.

## Direct Raw Validation

Direct V4L2 raw capture from `/dev/video0` was made to work at:

```text
BA10 / SGRBG10
1920x1080
bytesperline 3840
```

This established that the sensor driver and media graph could deliver stable raw frames without
PSYS.

The earlier bad-looking image was therefore not proof that raw capture was broken; it mostly showed
that raw Bayer without the proper ISP/AIQ pipeline is not a good final output.

## HAL Assets Added

Repo:

```sh
$HAL
```

GC2607 files added under `config/linux/ipu6epmtl`:

```text
gc2607_gc2607_MTL.aiqb
gcss/graph_settings_gc2607_gc2607_MTL.xml
gcss/graph_descriptor.xml
sensors/gc2607-uf.xml
```

`libcamhal_profile.xml` was modified to add:

```text
gc2607-uf-0
```

The installed copies are under:

```sh
~/opt/gc2607-ipu6/etc/camera/ipu6epmtl/
```

## Sensor XML

The GC2607 sensor XML was configured so the HAL's ISYS/producer side uses the Linux-stable
`1920x1080` mode:

```text
supportedISysSizes = 1920x1080
supportedISysFormat = V4L2_PIX_FMT_SGRBG10
supportedStreamConfig includes:
  V4L2_PIX_FMT_SGRBG10,1920x1080
  V4L2_PIX_FMT_NV12,1920x1080
```

The media-controller pad formats are also `1920x1080`.

This deliberately does not force the kernel sensor driver to output `1928x1088`.

## HAL Graph Experiments

Several graph-side attempts were tried before the final solution:

- patching graph settings to make the graph accept `1920x1080` directly
- changing only the active graph key
- changing broader top-level graph dimensions

Those graph edits validated as XML, but caused PSYS graph-configuration hangs or teardown failures
around `GraphConfigImpl::prepareGraphConfig()` / `GCSS::GraphConfigNode` destruction.

Those graph patches were reverted.

Conclusion: keep the Windows graph XML original and adapt the input buffer shape in HAL code.

## PSYS Padding Bridge

Implemented in:

```text
src/core/PSysProcessor.cpp
src/core/PSysProcessor.h
```

Purpose:

The sensor driver and ISYS producer deliver stable raw frames as:

```text
GRBG10 1920x1080
stride 3840
```

The Windows graph and PSYS pipeline expect:

```text
GRBG10 1928x1088
stride 3904
```

The bridge detects GC2607 with `V4L2_PIX_FMT_SGRBG10 1920x1080`, then:

1. adjusts only PSYS-side input frame info to `1928x1088`
2. leaves the CaptureUnit/producer at `1920x1080`
3. allocates/reuses synthetic USERPTR buffers sized for `1928x1088`
4. clears the padded buffer
5. copies each source row into the padded buffer at:
   - left offset: `4` pixels
   - top offset: `4` rows
6. passes the padded buffer to PSYS
7. keeps the original capture buffer mapped by sequence so it can be returned to ISYS after PSYS
   completes
8. recycles the padded buffers

Critical fix:

The synthetic padded buffers must be created with `BUFFER_USAGE_GENERAL`, not
`BUFFER_USAGE_PSYS_INPUT`.

Reason:

The HAL/CIPR path enables cache flushing for `BUFFER_USAGE_GENERAL`. Without that, PSYS could see
stale CPU-written memory. The symptom was coherent scene content with severe horizontal tearing.
Changing the usage fixed the tearing.

## Build And Install Commands

HAL build/install:

```sh
cd $HAL
cmake --build build-gc2607 -j"$(nproc)"
cmake --install build-gc2607 --prefix "$HOME/opt/gc2607-ipu6"
```

The installed HAL plugin used by the successful tests:

```text
~/opt/gc2607-ipu6/lib/libcamhal/plugins/ipu6epmtl.so
```

## Environment For HAL Tests

Use this environment when testing the local prefix:

```sh
PREFIX="$HOME/opt/gc2607-ipu6"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0"
export GST_REGISTRY="$PREFIX/gstreamer-registry.bin"
```

Stopping WirePlumber avoids it holding camera devices during tests:

```sh
systemctl --user stop wireplumber.service 2>/dev/null || true
```

## Successful Snapshot Test

Command:

```sh
systemctl --user stop wireplumber.service 2>/dev/null || true
PREFIX="$HOME/opt/gc2607-ipu6"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0"
export GST_REGISTRY="$PREFIX/gstreamer-registry.bin"
export cameraDebug=$((1|2|4|16))
rm -f /tmp/gc2607_pad_flush_*.png /tmp/gc2607-hal-pad-flush.log
timeout 45s gst-launch-1.0 -e -q \
  icamerasrc device-name=gc2607-uf num-buffers=30 \
  ! "video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1" \
  ! videoconvert \
  ! pngenc snapshot=false \
  ! multifilesink location=/tmp/gc2607_pad_flush_%02d.png \
  > /tmp/gc2607-hal-pad-flush.log 2>&1
```

Result:

```text
rc=0
/tmp/gc2607_pad_flush_29.png: PNG image data, 1920 x 1080, 8-bit/color RGB
```

The inspected frame was coherent ISP output with no horizontal corruption.

## Successful Sustained Test

Command:

```sh
systemctl --user stop wireplumber.service 2>/dev/null || true
PREFIX="$HOME/opt/gc2607-ipu6"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0"
export GST_REGISTRY="$PREFIX/gstreamer-registry.bin"
export cameraDebug=$((1|2|4))
rm -f /tmp/gc2607-hal-sustain.log
timeout 20s gst-launch-1.0 -e -q \
  icamerasrc device-name=gc2607-uf num-buffers=120 \
  ! "video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1" \
  ! fakesink sync=false \
  > /tmp/gc2607-hal-sustain.log 2>&1
```

Result:

```text
rc=0
padGc2607InputBuffers lines: 121
frame returned lines: 120
```

The only matched "fail" line was:

```text
fail to getMBRData for stream id:60001
```

No GStreamer data-flow failure, negotiation failure, or fatal PSYS error was present.

## Useful Log Lines From Working Run

These lines show the intended split between ISYS and PSYS:

```text
Producer config for port:0, fmt:GRBG10 (1920x1080), needProcessor=1
Enable GC2607 PSYS raw padding on port:0 (1920x1080 -> 1928x1088)
isSameStreamConfig: ipu6_lb_video_bayer ... internal: GRBG10(1928x1088: 3904), external: GRBG10(1928x1088: 3904)
allocProducerBuffers fmt:GRBG10 (1920x1080)
padGc2607InputBuffers, padded GC2607 input ... 1920x1080/3840 -> 1928x1088/3904
runPipe: Executor ipu6_lb_video_bayer
runPipe: Executor ipu6_bb_video_bayer
frame returned
```

## Current Git State Notes

HAL repo source-level changes:

```text
M config/linux/ipu6epmtl/libcamhal_profile.xml
M src/core/PSysProcessor.cpp
M src/core/PSysProcessor.h
?? config/linux/ipu6epmtl/gc2607_gc2607_MTL.aiqb
?? config/linux/ipu6epmtl/gcss/graph_settings_gc2607_gc2607_MTL.xml
?? config/linux/ipu6epmtl/sensors/gc2607-uf.xml
```

Also present but should not be part of source patch:

```text
build-gc2607/
libcamhal.pc
```

Driver repo source-level changes:

```text
M Makefile
M gc2607.c
```

Driver repo also contains many build/test artifacts from kernel builds and raw diagnostics.

## Upstream Considerations

The current HAL bridge is intentionally narrow and hard-coded for GC2607:

```text
1920x1080 -> 1928x1088
left pad = 4 pixels
top pad = 4 rows
format = SGRBG10
```

For upstream, a cleaner design would probably expose this as a data-driven raw input padding quirk,
for example from sensor XML or platform data, rather than hard-coding GC2607 in `PSysProcessor`.

The biggest non-code upstream risk is the AIQB/graph asset provenance. The working assets came from
the Windows driver package. Upstreaming those blobs may require explicit redistribution rights or a
different source.

## Recovery Commands If Devices Are Busy

If camera nodes are busy:

```sh
systemctl --user stop wireplumber.service
sudo fuser -v /dev/video* /dev/v4l-subdev* /dev/media*
```

If the sensor driver must be reloaded:

```sh
cd $DRIVER
echo i2c-GCTI2607:00 | sudo tee /sys/bus/i2c/drivers/gc2607/unbind
sudo rmmod gc2607
sudo insmod ./gc2607.ko
```

If bind reports "Device or resource busy", the device may already be bound.

## Bottom Line

Proceeding without AIQB files would be a lower-quality software ISP project. The Windows driver
assets were valuable and appear necessary for the best-quality IPU6 path.

The current working path is:

```text
GC2607 kernel driver, stable 1920x1080 raw
  -> IPU6 HAL producer at 1920x1080
  -> HAL GC2607 padding bridge to 1928x1088
  -> original Windows GC2607 graph + AIQB
  -> PSYS/AIQ ISP output as NV12 1920x1080
```
