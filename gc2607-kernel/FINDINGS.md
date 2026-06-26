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

## Open threads (30fps / MIPI)

- Exact sensor MIPI bit rate under the Windows PLL (the `MipiMBps` value the
  `.sys` reports to IPU6) was not pinned down — needed only if Path A is ever
  pursued for more exposure range.
- Roles of `0x0135` vs `0x0136` within the PLL (both move sclk together here).
- `0x0340` vs `0x0220` exact unit relationship (datasheet documents only `0x0340`).

---

# Phase 2 — HAL / icamerasrc image quality

Once 30 fps streamed cleanly on the raw node, the next target was real pictures
through the **icamerasrc / libcamhal (3A/ISP) path**, not just raw `/dev/video0`.
Capture script: `scripts/capture-gst-frame.sh` (uses `icamerasrc device-name=
gc2607-uf`, HAL prefix `~/opt/gc2607-ipu6`). The raw node never exercises 3A, so
these problems only show up via the HAL.

## Fixed: HAL 3A could not read frame timing (blown-out white frames)

Symptom: HAL log `failed to get llp` / `failed to get fll` / `Get sensor info
failed` / `run 3A failed`; images ~92% white (mean 60392/65535). Auto-exposure
never ran, so exposure stayed pinned near the default.

Cause: the HAL reads line-length/frame-length from the standard
`V4L2_CID_HBLANK` / `V4L2_CID_VBLANK` controls; the driver exposed neither. It
also advertised `pixel_rate` as the **MIPI-bus** rate (134.4 MHz), but the HAL
uses pixel_rate with llp/fll for frame-duration + exposure<->time conversion,
which needs the **sensor readout** rate.

Fix (shipped):
- Added `V4L2_CID_HBLANK` (read-only, `HTS-WIDTH = 39`) and `V4L2_CID_VBLANK`.
- Corrected `GC2607_PIXEL_RATE` to `HTS*VTS*30 ≈ 65.6 MHz` (readout rate).
- Made `VBLANK` writable (`36..2270`, VTS up to ~3350 / ~10fps): `s_ctrl` writes
  frame-length regs `0x0220/21` + `0x0340/41` and retracks the exposure ceiling
  via `__v4l2_ctrl_modify_range`. `EXPOSURE_MAX` now derives from VTS.

Result: real, correctly auto-exposed images (mean converges ~10k→26k over ~10
frames as AE settles). VBLANK writable was correct/standard but did NOT change
behaviour here (AE left vblank at 36) — it was not the remaining bug.

Also repaired post-restructure breakage: `scripts/install-gc2607-dkms.sh`
sourced from the deleted submodule (now `gc2607-kernel/`); `config/dkms/
gc2607-dkms.conf` now builds with `LLVM=1` (clang kernel).

## Fixed: grainy images = gain-model unit mismatch

Symptom: images auto-exposed but were **grainy in dim light**, and the HAL
logged `SetControl: /dev/v4l-subdev6 SetControl(int,int) error: Invalid
argument` (~12x at start).

Two-part root cause:
- The driver exposed **only `analogue_gain`, as a 0-16 LUT index**. The IPU6 HAL
  writes the AIQ's `analog_gain_code_global` straight to `V4L2_CID_ANALOGUE_GAIN`
  (`SensorHwCtrl::setAnalogGains`), and that code is in the units the
  `gc2607_gc2607_MTL.aiqb` CMC defines — which are **way above 16** — so the v4l2
  framework clamped every request to index 16 = 15.8x = **max analog gain,
  permanently**. That pinned gain is the grain; AE could only pull exposure down.
- `V4L2_CID_DIGITAL_GAIN` (written every frame by `setDigitalGains`) and the
  conditional `V4L2_CID_GAIN` were unimplemented -> `EINVAL` per write = the spam.

### Gain model, reverse-engineered from the .aiqb CMC

The authoritative units live in the CMC inside `gc2607_gc2607_MTL.aiqb` (CPFF /
`ia_mkn` container; record stream at file off `0x50`; record header
`{u32 size; u8 fmt; u8 key; u16 name_id}`; struct layouts from
`~/opt/gc2607-ipu6/include/ipu6epmtl/ia_imaging/ia_cmc_types.h`). Decoded:

- **Analog gain** — `cmc_name_id_multi_gain_conversions` (34): one analog,
  segment-type entry, SMIA coeffs **`M0=1 C0=0 M1=0 C1=64`** →
  `real_gain = code / 64`. Range `code_min=64` (1.0x) .. `code_max=2240` (35.0x),
  step 1. So **`V4L2_CID_ANALOGUE_GAIN` unit = 1/64**.
- **Digital gain** — `cmc_name_id_digital_gain` (20): `min=max=256`,
  `fraction_bits=8` → **fixed at 1.0x** (unit 1/256). The AIQ always writes
  `digital_gain_global = 256`. The sensor has no usable standalone digital-gain
  register (reference `set_digital_gain` is a no-op, `max_dgain=0`); 0x020c/0x020d
  are the analog fine-trim consumed by the `again` table.
- `cmc_name_id_analog_gain_conversion` (19) is the deprecated path and is empty.

The GalaxyCore `again` table (regs 0x02b3/0x02b4 analog + 0x020c/0x020d fine-trim,
17 entries 1.0x..15.8125x) was recovered from git
`343ca59^:gc2607-kernel/reference/gc2607.c`. Its real-gain values × 64 give the
LUT's analog-gain codes: 64, 76, 93, 111, 130, 156, 184, 221, 253, 304, 367, 434,
510, 607, 717, 847, 1012.

Caveat on the reference table: its `gain` column is **not** linear — it is
Ingenic T41 ISP units, `log2(real_gain) × 65536` (e.g. 1.1875x → 16247 ≈
`log2(1.1875)·65536`; 15.8125x → 261029). The usable real-gain figures are the
per-row comments (1.0, 1.1875, 1.453125, …, 15.8125), which is what `×64` above
is applied to. `alloc_dgain` returns 0 / `max_dgain = 0`, confirming digital gain
is unused in the reference — consistent with the CMC fixing it at 1.0x.

Cross-check that closed the loop: the SMIA formula `code/64` reproduces the LUT
endpoints exactly (code 1012 → 15.8125x = LUT max; code 64 → 1.0x = LUT min), and
all 17 reference real-gains map cleanly inside the CMC's `[64, 2240]` code range.

### How it was decoded (reproduce)

- The Windows `gc2607.sys` was disassembled (radare2) first, since the original
  plan assumed the gain LUT lived there. It does **not**: the gain-apply function
  (a mutex-guarded read-modify-write of 0x0202/0x0203 exposure + 0x02b3/0x02b4 +
  0x020c/0x020d, via the i2c helper at VA 0x140005088) pulls already-computed
  values from a struct, and no 17-entry again byte-table is present — the `.sys`
  computes gain by formula from the AIQ code. So the **CMC in the `.aiqb` is the
  authoritative source**, not the `.sys`. (The `.sys` still holds the init
  register descriptor table at `.rdata` VA 0x140022c30, matching
  `tools/win_gc2607_regs.txt`.)
- CMC record stream start (file off `0x50`) and per-record alignment were found by
  walking the `{u32 size,…}` size-chain until it produced a long valid run of
  records. Relevant records, by file offset:
  `name 19 (analog_gain_conversion, deprecated/empty) @0x020390`,
  `name 20 (digital_gain) @0x0203a0`,
  `name 34 (multi_gain_conversions) @0x029e48` with its `cmc_gain_segment_t`
  (gain_begin/end floats + code_min/max/step + M0/C0/M1/C1) at `@0x029e90`.
- HAL data-flow that fixes the units to V4L2 (paths under `third_party/
  ipu6-camera-hal/src/`): `3a/SensorManager.cpp` pushes
  `exp.sensorParam.analog_gain_code_global` / `digital_gain_global`, then
  `core/SensorHwCtrl.cpp` writes them: `setAnalogGains()` →
  `SetControl(V4L2_CID_ANALOGUE_GAIN)` (~L354); `setDigitalGains()` →
  `SetControl(V4L2_CID_DIGITAL_GAIN)` **every frame** (~L392) and
  `SetControl(V4L2_CID_GAIN)` **only if** `isUsingSensorDigitalGain` (~L385).
  Hence DIGITAL_GAIN is the one that must exist; GAIN is conditional.

### Shipped fix

- `V4L2_CID_ANALOGUE_GAIN` now in **1/64 units, min 64 (1.0x), max 1012
  (15.8125x = again-LUT ceiling), default 64**. `s_ctrl` calls
  `gc2607_again_for_code()` to round the requested code down to the nearest
  again-table entry and writes its four registers.
- Added `V4L2_CID_DIGITAL_GAIN` (256..256, fixed 1.0x) as an accepted no-op so
  the HAL's per-frame writes stop returning EINVAL; `V4L2_CID_GAIN` shares the
  same no-op case for the conditional `isUsingSensorDigitalGain` path.

Result (hardware): controls now read `analogue_gain min=64 max=1012`,
`digital_gain 256`; 30fps stays clean; AE ramps smoothly from gain default and
settles on a **low** analog code in normal light → real, correctly-exposed,
**non-grainy** images (verified visually). The `SetControl Invalid argument` spam
is gone.

Note: analog gain above 15.8x (CMC allows up to 35x) is not realized — it would
need the digital path, which this tuning fixes at 1.0x. Fine for a webcam; AE
pulls exposure first and only saturates gain in very dark scenes. If real digital
gain is ever wired up: the CMC `digital_gain_global` is in 1/256 units while the
sensor's 0x020c:0x020d register pair is 1/64 (0x0040 = 1.0x), so register =
code / 4 — but note 0x020c/0x020d is already consumed by the analog fine-trim, so
a separate dgain register (or ISP digital gain) would be needed to avoid a clash.

Upstreaming: register addresses/values and the `gain = code/64` formula are
functional hardware facts (gc05a2/gc08a3/gc2145 ship mainline with opaque
register tables). All of it is re-expressed in our own code; no disassembled C,
strings, or copyrighted text from the binary was copied. File is SPDX GPL-2.0,
and standard ANALOGUE_GAIN/DIGITAL_GAIN semantics move it toward upstreamable
shape.

## Build / reload / test reference

```bash
# build (clang kernel -> LLVM=1 required)
cd gc2607-kernel && make LLVM=1

# reload the freshly-built .ko (reuses the proven reloader)
sudo ./tools/pll_sweep.sh "reload:"

# inspect controls (subdev path may differ; find via v4l2-ctl --list-subdevs)
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls

# HAL capture (3A/ISP path) + brightness sanity
cd .. && ./scripts/capture-gst-frame.sh /tmp/gc2607-frame 10
identify -format '%f mean=%[mean]\n' /tmp/gc2607-frame-*.jpg   # ~32768 = mid-gray

# persistent install (DKMS) once happy
sudo dkms remove gc2607/0.1.0 --all && sudo ./scripts/install-gc2607-dkms.sh
```

Notes:
- Running module is the **DKMS** build (`/lib/modules/.../updates/dkms/`), separate
  from `gc2607-kernel/`. Editing the source needs a reload (above) or DKMS reinstall.
- The `Failed to open /run/camera/gc2607-uf_VIDEO.aiqd` warning is harmless (no
  cached tuning file on first run; HAL falls back to the `.aiqb`).
- `pixel_rate`/`hblank` are read-only; `vblank` is writable (36..2270).

## Open threads (HAL)

- Gain model RE — **done** (see "Fixed: grainy images" above). `V4L2_CID_GAIN`
  shares the digital-gain no-op case; only `DIGITAL_GAIN` is written unconditionally.
- Analog gain >15.8x (CMC allows 35x) not realized — would need a working digital
  path, which the current tuning fixes at 1.0x. Revisit only if low-light is poor.
- AE settling: each fresh pipeline start ramps from the gain default; a few frames
  to converge. Tune default/initial-skip if first-frame latency matters.
- Lens shading / color: not yet evaluated (focus has been exposure/gain).
