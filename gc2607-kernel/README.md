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

## 30 fps at 1080p

The default mode is **1920×1080 @ 30 fps**. Getting there was non-obvious: the
init register set is inherited from the T41 reference driver, whose PLL is tuned
for a **24 MHz** MCLK. This board feeds **19.2 MHz**, so the same dividers
under-clock the sensor (~65.6 MHz pixel clock → 24 fps) — see `tools/PLL_SWEEP.md`.

Two ways to reach 30 fps were validated on hardware:

| approach | result |
|----------|--------|
| Windows-driver PLL (sclk → ~103 MHz) | 30 fps, but CSI **CRC errors** (MIPI clock leaves the IPU6's locked 672 Mbps) |
| **shipped:** stock PLL + tight blanking (`HTS=1959`, `VTS=1116`) | **30 fps, clean** — no ipu-bridge / `link_freq` changes |

The shipped default keeps the stock PLL so the MIPI link stays at the 672 Mbps
the IPU6 receiver expects, and hits 30 fps by running near-minimum blanking.
Tradeoff: max exposure is capped at ~1100 lines (VTS−16).

## tools/ — PLL/timing sweep harness

Experimental module params (`reg0134…reg0d06`, `hts`, `vts`, `frame_len`) patch
registers **in-sequence** during init so PLL changes apply before the PLL locks.
Default `-1` = stock. Used to bisect the 30 fps fix and to verify register sets
extracted from the Windows driver.

```bash
make LLVM=1
sudo ./tools/pll_sweep.sh "stock:" "win30:reg0135=0x05 reg0136=0x42 reg031c=0xf3 hts=2745 vts=1250 frame_len=1250"
```

- `tools/PLL_SWEEP.md` — full method, register meanings, Windows ground-truth values
- `tools/win_gc2607_regs.txt` — 278-entry register table extracted from the
  Windows IPU6 `gc2607.sys` (1928×1088 @ 30 fps, 19.2 MHz)

## Controls

- `V4L2_CID_EXPOSURE` — 4…1100 lines (0x0202/0x0203)
- `V4L2_CID_ANALOGUE_GAIN` — LUT index 0…16 (0x02b3/0x02b4/0x020c/0x020d)
- `V4L2_CID_LINK_FREQ` — 336 MHz (read-only); `V4L2_CID_PIXEL_RATE` — 134.4 MHz
