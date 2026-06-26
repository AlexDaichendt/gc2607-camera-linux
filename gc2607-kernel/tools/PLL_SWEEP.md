# GC2607 PLL / timing sweep harness

Experimental tooling to find the register set that gives a clean **30 fps** at
1080p on the MateBook (19.2 MHz MCLK). Branch: `pll-sweep`.

## Why

The sensor runs 24.00 fps, not 30. The init register set is byte-identical to
the GalaxyCore T41 reference driver, which feeds the sensor **24 MHz** MCLK
(`clk_set_rate(mclk, 24000000)`). The MateBook's INT3472 feeds **19.2 MHz**, so
the same PLL dividers produce `19.2/24 = 0.8x` the pixel clock: 65.6 MHz instead
of 82 MHz, i.e. 24 fps instead of 30. The datasheet rates the part at 60 fps
full-size, so 30 fps is well within reach once the PLL is configured for the
actual input clock. Datasheet says line length (`0x0342`, default 2048) is *not*
the lever — leave it alone; the PLL block is.

## How it works

`gc2607.ko` gains module params that override one register each, applied **after**
the mode init array in `s_stream()`. Default `-1` = keep the init value, so the
stock build is unchanged.

| Param      | Register | Init | Role (per reference + datasheet) |
|------------|----------|------|----------------------------------|
| `reg0134`  | 0x0134   | 0x5b | PLL multiplier (primary knob)    |
| `reg0135`  | 0x0135   | 0x01 | PLL                              |
| `reg0136`  | 0x0136   | 0x2a | PLL                              |
| `reg0137`  | 0x0137   | 0x03 | PLL                              |
| `reg0315`  | 0x0315   | 0xd4 | system/readout divider           |
| `reg031c`  | 0x031c   | 0x93 | system/MIPI divider              |
| `reg0d06`  | 0x0d06   | 0x01 | PLL/clock enable                 |
| `vts`      | 0x0220/1 | 1335 | frame length (re-trim fps)       |
| `frame_len`| 0x0340/1 | 2670 | datasheet frame length (= 2x VTS)|

```bash
# manual single shot
make LLVM=1                    # CachyOS kernel is clang-built; LLVM=1 is required
sudo insmod gc2607.ko reg0134=0x72 vts=1335
dmesg | grep PLL-SWEEP         # confirms which overrides were written
```

## Windows ground truth (use this first — no blind sweep needed)

The Windows IPU6 driver (`gc2607.sys`, MTL build) runs this sensor on the **same
19.2 MHz MateBook at 30 fps**. Its register init table was extracted and diffed
against the Linux init. The clock/timing registers that differ:

| reg            | Windows | Linux | note                         |
|----------------|---------|-------|------------------------------|
| 0x0135 (PLL)   | 0x05    | 0x01  |                              |
| 0x0136 (PLL)   | 0x42    | 0x2a  |                              |
| 0x031c (div)   | 0xf3    | 0x93  |                              |
| 0x0342/43 HTS  | 0x0ab9 = **2745** | 0x0800 = 2048 | line length |
| 0x0340/41      | 0x04e2 = **1250** | 0x0a6e = 2670 | frame length |
| 0x0220/21 VTS  | 0x04e2 = **1250** | 0x07d3 = 2003 | frame length |

`0x0134` (PLL multiplier) is **unchanged** (0x5b) — the retune is in 0x0135/0x0136
plus the 0x031c divider. Windows uses HTS=2745 (neither the datasheet's 1200 nor
the init's 2048) and VTS=frame_len=1250 (the Linux `0x0340 = 2*VTS` was a T41
porting quirk). Implied pixel clock ~ `30 x 1250 x 2745 = 103 MHz`.

Apply exactly that and measure:

```bash
make LLVM=1
sudo ./tools/pll_sweep.sh \
    "stock:" \
    "win30:reg0135=0x05 reg0136=0x42 reg031c=0xf3 hts=2745 vts=1250 frame_len=1250"
```

Expected: `win30` → 30.00 fps. If the errors column is clean, fold the six
values into `gc2607_1080p_30fps_regs[]` and you're done. If CSI errors appear,
the MIPI rate moved past what the ipu-bridge expects (336 MHz / 672 Mbps) — raise
`GC2607_LINK_FREQ` and the ipu-bridge `IPU_SENSOR_CONFIG("GCTI2607", ...)`
together. (Payload at 30 fps is only ~360 Mbps/lane, so the 672 link likely still
locks — that's what this run confirms.) Full Windows table: `tools/win_gc2607_regs.txt`.

> Note: VTS drops 2003 → 1250, so lower exposure when testing
> (`v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1200`) — the driver's
> EXPOSURE_MAX (2002) now exceeds the frame length.

## Manual sweep (if you need to explore beyond the Windows values)

```bash
make LLVM=1
sudo ./tools/pll_sweep.sh \
    "stock:" \
    "m60:reg0134=0x60" \
    "m6c:reg0134=0x6c" \
    "m72:reg0134=0x72" \
    "m72_vts:reg0134=0x72 vts=1335"
```

For each point it reloads the driver, brings up the raw-ISYS pipeline
(`/dev/video0`, BA10, no ISP/3A), streams 150 frames, records fps, and scans
dmesg for CSI/PLL errors. Output goes to `results.csv`.

## Reading results / bisecting

- **fps scales up, errors column clean** → good direction, keep raising `reg0134`.
- **fps scales up but CSI errors appear** → the MIPI clock rose past 672 Mbps and
  the IPU6 receiver lost lock. The CSI rate is pinned by the ipu-bridge
  `IPU_SENSOR_CONFIG("GCTI2607", 1, 336000000)`, so either:
  1. pull a divider back down in the same point (e.g. add `reg031c=...`) to keep
     MIPI at 672 Mbps while readout rises (there's bandwidth headroom — 1080p30
     RAW10 is ~622 Mbit/s vs 1344 Mbit/s on 2 lanes), or
  2. raise the driver's `GC2607_LINK_FREQ` **and** the ipu-bridge config together.
- **target:** `30.00 fps` with an empty errors column. Then fold the winning
  values into `gc2607_1080p_30fps_regs[]` and drop the module params.

> Goal is exactly 30 fps. `reg0134` is a guess at the multiplier encoding; the
> Windows IPU6 driver's PLL block for 19.2 MHz is the authoritative source for
> the real values — use this harness to *verify* whatever it yields on hardware.
