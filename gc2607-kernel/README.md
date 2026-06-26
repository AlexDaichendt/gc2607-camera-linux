# GC2607 V4L2 driver (Intel IPU6 / Meteor Lake)

Linux V4L2 sensor driver for the GalaxyCore **GC2607** (1/7.3" 1080p RAW10 Bayer,
2-lane MIPI CSI-2) as wired on the HUAWEI MateBook (Intel IPU6, INT3472 PMIC,
19.2 MHz MCLK). Ported from the GalaxyCore Ingenic T41 reference driver.

## Build

The CachyOS/Arch kernel here is **clang-built**, so the out-of-tree build needs
the LLVM toolchain:

```bash
make LLVM=1
```

`make clean` to remove artifacts. Produces `gc2607.ko`.

## Load & capture

```bash
sudo modprobe videodev v4l2-async intel-ipu6 intel-ipu6-isys ipu_bridge
sudo insmod gc2607.ko
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=150 --stream-to=/dev/null
```

Sensor output is `SGRBG10_1X10` (BA10 on the video node). Requires the modified
`ipu_bridge` carrying `IPU_SENSOR_CONFIG("GCTI2607", 1, 336000000)`.

This raw `/dev/video0` node bypasses 3A/ISP, so it is the cleanest way to verify
sensor timing (fps) but produces unprocessed Bayer, not a viewable picture.

## DKMS install & dev reload

For day-to-day work the driver is packaged with DKMS (built `LLVM=1`, rebuilt
automatically on kernel upgrades). From the repo root:

```bash
sudo ../scripts/install-gc2607-dkms.sh        # build + install gc2607/0.2.0
sudo ../scripts/reload-gc2607.sh              # rebuild + hot-reload + fps check
sudo ../scripts/reload-gc2607.sh --no-build   # reload the installed module only
```

`reload-gc2607.sh` exists because the sensor subdev is held by
`intel-ipu6-isys` once probed, so `rmmod gc2607` alone fails — the script tears
down the ISYS/IPU6 stack first, swaps the module, and brings the pipeline back
up. Edit `gc2607.c`, run it, done.

## Live preview (HAL / icamerasrc)

A real, auto-exposed picture comes through the IPU6 HAL (3A + ISP), not the raw
node. From the repo root (needs the `~/opt/gc2607-ipu6` HAL prefix):

```bash
../scripts/view-gst-live.sh          # live window via icamerasrc
../scripts/capture-gst-frame.sh      # grab 30 JPEG frames instead
```

Equivalent one-liner (what the script runs):

```bash
PREFIX="$HOME/opt/gc2607-ipu6"
LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/libcamhal/plugins" \
GST_PLUGIN_PATH="$PREFIX/lib/gstreamer-1.0" \
GST_REGISTRY="$PREFIX/gstreamer-registry.bin" \
gst-launch-1.0 -v \
    icamerasrc device-name=gc2607-uf \
    ! video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1 \
    ! videoflip method=rotate-180 \
    ! videoconvert \
    ! autovideosink sync=false
```

The camera is mounted upside-down, hence `videoflip method=rotate-180`
(`GC2607_FLIP_METHOD=none` to disable). Override the sink with
`GC2607_SINK=waylandsink` if `autovideosink` misbehaves on Wayland.

## 30 fps at 1080p

The default mode is **1920×1080 @ 30 fps**. Getting there was non-obvious: the
init register set is inherited from the T41 reference driver, whose PLL is tuned
for a **24 MHz** MCLK. This board feeds **19.2 MHz**, so the same dividers
under-clock the sensor (~65.6 MHz pixel clock → 24 fps) — see `FINDINGS.md`.

Two ways to reach 30 fps were validated on hardware:

| approach | result |
|----------|--------|
| Windows-driver PLL (sclk → ~103 MHz) | 30 fps, but CSI **CRC errors** (MIPI clock leaves the IPU6's locked 672 Mbps) |
| **shipped:** stock PLL + tight blanking (`HTS=1959`, `VTS=1116`) | **30 fps, clean** — no ipu-bridge / `link_freq` changes |

The shipped default keeps the stock PLL so the MIPI link stays at the 672 Mbps
the IPU6 receiver expects, and hits 30 fps by running near-minimum blanking.
Tradeoff: max exposure is capped at ~1100 lines (VTS−16).

## tools/

- `tools/win_gc2607_regs.txt` — 278-entry register table extracted from the
  Windows IPU6 `gc2607.sys` (1928×1088 @ 30 fps, 19.2 MHz), kept as ground-truth
  reference for the timing/PLL values. The historical PLL-sweep harness (module
  params + `pll_sweep.sh`) that bisected the 30 fps fix has been removed now that
  the values are baked into the init array; see `FINDINGS.md` for the method.

## Controls

- `V4L2_CID_EXPOSURE` — 4…(VTS−8) lines, default 1000 (0x0202/0x0203)
- `V4L2_CID_ANALOGUE_GAIN` — 64…1012 in **1/64 units** (1.0×…15.8125×), rounded
  down to the nearest again-table entry (0x02b3/0x02b4 + 0x020c/0x020d fine-trim)
- `V4L2_CID_DIGITAL_GAIN` — fixed 256 (1.0×); accepted no-op so the HAL's
  per-frame writes don't `EINVAL`. `V4L2_CID_GAIN` shares the same no-op.
- `V4L2_CID_VBLANK` — writable, 36…2270 (drives VTS for low-light AE; exposure
  max tracks it). `V4L2_CID_HBLANK` — read-only (39).
- `V4L2_CID_LINK_FREQ` — 336 MHz (read-only)
- `V4L2_CID_PIXEL_RATE` — ~65.6 MHz, read-only (sensor **readout** rate used by
  HAL 3A for frame-duration / exposure↔time, not the MIPI bus rate)
