# GC2607 1080p30 bring-up — findings

Investigation into why the GC2607 streamed below 30 fps on the HUAWEI MateBook
(Intel IPU6 / Meteor Lake, 19.2 MHz MCLK), and how it was fixed. All register
addresses are 16-bit, values 8-bit.

## TL;DR

- The driver's init register set is **byte-for-byte the GalaxyCore Ingenic T41
  reference driver**, whose PLL is tuned for a **24 MHz** input clock.
- This board feeds the sensor **19.2 MHz** (INT3472 platform clock). Same PLL
  dividers → pixel clock scales by `19.2/24 = 0.8` → **65.6 MHz instead of
  82 MHz → 24 fps instead of 30** (and 16 fps with the later `VTS=2003`).
- Datasheet line-length "1200" and the init's "2048" were both **red herrings**.
- Two routes to 30 fps were validated on hardware. The **shipped fix keeps the
  stock PLL** (so the MIPI link stays at the IPU6's locked 672 Mbps) and reaches
  30 fps by shrinking blanking: **HTS=1959, VTS=frame_len=1116**. Clean, no
  ipu-bridge changes.

## Evidence chain

### 1. Measured ceiling
Raw ISYS capture (`/dev/video0`, BA10, no ISP/3A):
```
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=150 --stream-to=/dev/null
```
Stock build → a rock-steady 24.00 fps (16 fps with `VTS=2003`). The fps obeys a
clean inverse law `fps = sclk / (HTS × VTS)`, giving `sclk ≈ 65.6 MHz`:

```
sclk = 24.0 × 1335 × 2048 ≈ 65.6 MHz
```

### 2. The init is the T41 reference, verbatim
`reference/gc2607.c` (the T41 driver) and the ported init array share the exact
timing + PLL block, including the comment `//hts=2048`:

```
{0x0342,0x08}, {0x0343,0x00},  // hts = 2048
{0x0220,0x05}, {0x0221,0x37},  // vts = 1335
PLL: 0x0134=0x5b 0x0135=0x01 0x0136=0x2a 0x0137=0x03 0x0315=0xd4 0x031c=0x93 0x0d06=0x01
```

The T41 reference declares its target clock explicitly:
```c
sclk = 1335 * 2048 * 30;              // = 82.0 MHz  (reference/gc2607.c)
private_clk_set_rate(sensor->mclk, 24000000);   // 24 MHz MCLK
```

### 3. The clock arithmetic closes exactly
- Reference: 24 MHz MCLK → 82 MHz sclk → 30 fps.
- MateBook: 19.2 MHz MCLK, same PLL → `82 × 19.2/24 = 65.6 MHz` → 24 fps.
- `19.2/24 = 0.8 = 24/30` exactly. Measurement matches to the digit.

### 4. Datasheet (GC2607 CSP Preliminary V0.1)
- **Max frame rate: 60 fps @ full size** (30 fps is only the HDR-mode figure) —
  so 30 fps is nowhere near a sensor ceiling; it's purely a clock-config issue.
- **Input clock typ = 24 MHz** (range 6–27); operation-current test condition is
  "Input clock 27 MHz, 30 FPS, RAW10". Confirms 24 MHz is the design point.
- **Line length contradiction:** the function section says `0x0342/0x0343` =
  "Line length = 1200 (not recommended to modify)", but the Register List says
  `0x0342 = CISCTL_hb`, default `0x08`/`0x00` = **2048**. The register **default
  is 2048**, so 2048 is correct and "1200" is a doc inconsistency. → do **not**
  change line length to chase fps.
- Official frame-length register is **`0x0340/0x0341`** (`0x0220/0x0221` is
  undocumented). The T41 init sets `0x0340 = 2×VTS`; the Windows driver sets
  `0x0340 == 0x0220`, so the `2×` was a T41 quirk.

## Windows-driver ground truth

The Windows IPU6 package (`Camera_IPU6_64.22000.13.14550.exe`) runs this exact
sensor at 30 fps on 19.2 MHz. Extraction:

- NSIS installer → nested NSIS → `camera/gc2607.sys` (PE32+, 189 KB).
- Register init table in `.rdata` at file offset **0x210c0**, as 16-byte entries
  `{u32 flag, u32 addr, u32 val, u32 pad}`, 278 entries → `tools/win_gc2607_regs.txt`.
- Mode descriptor: `1928×1088`, `fps=0x1e` (30), `llp=0x0ab9` (2745).

Diff of the Windows table vs the Linux init (clock/timing registers):

| reg            | Windows           | Linux            | meaning            |
|----------------|-------------------|------------------|--------------------|
| 0x0134         | 0x5b              | 0x5b (unchanged) | PLL multiplier     |
| 0x0135         | **0x05**          | 0x01             | PLL                |
| 0x0136         | **0x42**          | 0x2a             | PLL                |
| 0x031c         | **0xf3**          | 0x93             | system/MIPI divider|
| 0x0342/43 HTS  | **0x0ab9 = 2745** | 0x0800 = 2048    | line length        |
| 0x0340/41      | **0x04e2 = 1250** | 0x0a6e = 2670    | frame length       |
| 0x0220/21 VTS  | **0x04e2 = 1250** | 0x07d3 = 2003    | frame length       |

Implied Windows pixel clock: `30 × 2745 × 1250 ≈ 103 MHz`. The PLL multiplier
(`0x0134`) is unchanged — the retune lives in `0x0135/0x0136` + the `0x031c`
divider.

## Hardware results

Tested via the `tools/pll_sweep.sh` harness (module-param register overrides
applied **in-sequence during init**, so PLL writes land before the PLL locks):

| test point | params | fps | CSI |
|------------|--------|-----|-----|
| stock | — | 16.12 | clean |
| winA (Windows PLL) | `reg0135=0x05 reg0136=0x42 reg031c=0xf3 hts=2745 vts=1250 frame_len=1250` | 30.02 | **CRC errors** |
| winA_revdiv | as winA but `reg031c=0x93` | 30.02 | **CRC errors** |
| **pathB (shipped)** | `hts=1959 vts=1116 frame_len=1116` (stock PLL) | **29.90** | **clean** |

Interpretation:
- **winA** proves the clock fix works (PLL relocked → 30.02 fps) but raising
  sclk to ~103 MHz moves the sensor MIPI clock off the **672 Mbps** the IPU6
  CSI receiver is locked to (set by the ipu-bridge `IPU_SENSOR_CONFIG`), so the
  D-PHY mis-samples → payload CRC errors. Reverting `0x031c` didn't help, so it
  doesn't gate sclk or set the MIPI rate alone.
- **pathB** keeps the stock PLL (MIPI stays at the known-good 672 Mbps → zero
  CRC) and reaches 30 fps by tightening blanking: `65.6e6/(1959×1116) = 30.0`.

A key sub-finding: applying PLL overrides **after** the full init does nothing —
the PLL has already locked (this is why the first winA attempt stayed at 65.6
MHz / 19 fps). The harness now patches values inside the init write loop.

## Shipped fix (pathB)

Default mode = 1920×1080 @ 30 fps, stock PLL:

```
HTS  0x0342/0x0343 = 0x07a7 = 1959   (≈39 px h-blank — near minimum)
VTS  0x0220/0x0221 = 0x045c = 1116   (min frame length: 1080 + 20 + 16)
FLL  0x0340/0x0341 = 0x045c = 1116
EXPOSURE_MAX = 1100  (< VTS)
PLL, link_freq (336 MHz), pixel_rate (134.4 MHz): unchanged
```

**Tradeoffs:** near-minimum horizontal/vertical blanking; max exposure capped at
~1100 lines (vs 2003 before). Streams clean over 150 frames. If more exposure
headroom is ever needed, switch to the Windows PLL and update `GC2607_LINK_FREQ`
**and** the ipu-bridge `IPU_SENSOR_CONFIG` to the real MIPI rate together
(payload at 30 fps is only ~360 Mbps/lane, so 672 has headroom but the PHY must
be told the actual rate).

## Reproduce / experiment

```bash
make LLVM=1                         # CachyOS kernel is clang-built
sudo ./tools/pll_sweep.sh \
    "stock:" \
    "winPLL:reg0135=0x05 reg0136=0x42 reg031c=0xf3 hts=2745 vts=1250 frame_len=1250"
```

See `tools/PLL_SWEEP.md` for the param table and method.

## Open threads

- Exact sensor MIPI bit rate under the Windows PLL (the `MipiMBps` value the
  `.sys` reports to IPU6) was not pinned down — needed only if Path A is ever
  pursued for more exposure range.
- Roles of `0x0135` vs `0x0136` within the PLL (both move sclk together here).
- `0x0340` vs `0x0220` exact unit relationship (datasheet documents only `0x0340`).
