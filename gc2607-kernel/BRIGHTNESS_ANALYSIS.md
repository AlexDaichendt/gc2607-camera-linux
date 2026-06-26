# GC2607 Brightness Analysis - Beyond Maximum Exposure & Gain

## Current Limitations
- Maximum exposure: 1334 lines (VTS-1)
- Maximum gain: LUT index 16 (15.8x gain)
- Image still too dark even at maximum settings

## Key Findings from Reference Driver Analysis

### 1. DIGITAL GAIN REGISTERS (0x020c, 0x020d)

**Critical Discovery:** These registers are part of the gain LUT but can potentially be manipulated independently!

From reference driver (lines 58-77):
```c
struct again_lut {
    unsigned int reg2b3;  // Analog gain H
    unsigned int reg2b4;  // Analog gain L
    unsigned int reg20c;  // DIGITAL GAIN H  <-- KEY!
    unsigned int reg20d;  // DIGITAL GAIN L  <-- KEY!
    unsigned int gain;
};
```

**LUT Table Analysis:**
- Index 0: 0x020c=0x00, 0x020d=0x40 (baseline)
- Index 8: 0x020c=0x01, 0x020d=0x00 (digital boost starts)
- Index 16: 0x020c=0x04, 0x020d=0x00 (maximum in LUT)

**Potential Override:** 
The registers 0x020c and 0x020d appear to be DIGITAL gain multipliers.
Current max: 0x0400 (from LUT index 16)
**Hypothesis:** We could try values BEYOND the LUT maximum, such as:
- 0x020c=0x08, 0x020d=0x00 (2x beyond LUT max)
- 0x020c=0x10, 0x020d=0x00 (4x beyond LUT max)

**Risk:** This is beyond spec and may introduce noise, but could boost brightness significantly.

---

### 2. VTS EXTENSION FOR LONGER EXPOSURE

**Current VTS:** 1335 lines (registers 0x0220=0x05, 0x0221=0x37)
**Current Max Exposure:** 1334 lines (VTS-1)

From reference driver function `gc2607_set_fps()` (lines 545-591):
```c
vts = sclk * (fps & 0xffff) / hts / ((fps & 0xffff0000) >> 16);
ret = gc2607_write(sd, 0x0220, (unsigned char)((vts >> 8) & 0xff));
ret += gc2607_write(sd, 0x0221, (unsigned char)(vts & 0xff));
sensor->video.attr->max_integration_time = vts - 1;
```

**This shows VTS is DYNAMICALLY ADJUSTABLE!**

**Opportunity for Brightness Boost:**
1. Increase VTS to allow longer exposures
2. Trade-off: Frame rate will decrease proportionally

**Example Calculations:**
- Current: VTS=1335, max_exposure=1334, FPS=30
- Double exposure: VTS=2670, max_exposure=2669, FPS=15
- Triple exposure: VTS=4005, max_exposure=4004, FPS=10
- Quadruple: VTS=5340, max_exposure=5339, FPS=7.5

**Implementation:**
```c
// In gc2607.c, modify GC2607_VTS and GC2607_EXPOSURE_MAX
#define GC2607_VTS_EXTENDED     4005    // Triple the exposure time
#define GC2607_EXPOSURE_MAX     4004    // FPS drops to 10

// Update initialization sequence registers
{0x0220, 0x0f},  /* VTS high byte (4005 = 0x0fa5) */
{0x0221, 0xa5},  /* VTS low byte */
```

---

### 3. BLACK LEVEL / OFFSET REGISTERS

From initialization sequence (lines 229-237):
```c
{0x0070, 0x40},  // Black level/offset related?
{0x0071, 0x40},
{0x0072, 0x40},
{0x0073, 0x40},
{0x0040, 0x82},  // Possible ISP control
{0x0030, 0x80},  // Offset/pedestal registers
{0x0031, 0x80},
{0x0032, 0x80},
{0x0033, 0x80},
```

**Hypothesis:** Registers 0x0030-0x0033 and 0x0070-0x0073 appear to be offset/black level controls.

**Current values:** 0x80, 0x40 (midpoint values)

**Potential adjustment to boost brightness:**
- REDUCE black level subtraction: Change 0x0040-0x0073 from 0x40 to 0x20 (subtract less)
- REDUCE pedestal: Change 0x0030-0x0033 from 0x80 to 0x60 (lower black point)

**Risk:** May introduce false brightness or reduce dynamic range, but could help.

---

### 4. ISP BRIGHTNESS/GAMMA REGISTERS

From initialization (lines 228, 256, 270-279):
```c
{0x0089, 0x03},   // Possible ISP control register
{0x0082, 0x03},   // Another ISP control
{0x00d0, 0x0d},   // Possible gamma/curve control
{0x00d6, 0x00},   // Related control
{0x00e0, 0x18},   // Gamma LUT? (8 consecutive registers)
{0x00e1, 0x18},
{0x00e2, 0x18},
{0x00e3, 0x18},
{0x00e4, 0x18},
{0x00e5, 0x18},
{0x00e6, 0x18},
{0x00e7, 0x18},
```

**Hypothesis:** 0x00e0-0x00e7 appear to be gamma curve registers (all set to 0x18 = 24 decimal).

**Potential brightness boost:**
- INCREASE gamma values: Change from 0x18 to 0x20 or 0x30
- This would lift the midtones and shadows

**Additional registers to investigate:**
- 0x0089: Try increasing from 0x03 to 0x07 (might be brightness control)
- 0x00d0: Try different values (0x0d → 0x10 or 0x18)

---

### 5. DIGITAL GAIN FUNCTION (Line 106-109)

**CRITICAL FINDING:**
```c
unsigned int gc2607_alloc_dgain(unsigned int isp_gain, unsigned char shift, unsigned int *sensor_dgain)
{
    return 0;  // DIGITAL GAIN IS NOT IMPLEMENTED!
}
```

The reference driver has a **stub function** for digital gain allocation. This suggests:
1. The sensor SUPPORTS digital gain beyond the analog gain
2. The T41 ISP handles digital gain, not the sensor driver
3. **We could implement independent digital gain control!**

**Implementation opportunity:**
Add a new V4L2 control `V4L2_CID_DIGITAL_GAIN` that directly manipulates 0x020c/0x020d beyond the LUT values.

---

### 6. OTHER SUSPICIOUS BRIGHTNESS-RELATED REGISTERS

From initialization sequence:
```c
{0x00c0, 0x07},  // Unknown, might be brightness-related
{0x00c1, 0x90},  // Unknown, might be brightness-related
{0x00c3, 0x3c},  // Unknown
```

These are set early in init and could affect overall sensor brightness/sensitivity.

---

## RECOMMENDED IMPLEMENTATION STRATEGY

### Phase 1: VTS Extension (SAFEST)
1. Increase VTS to 4005 (triple exposure capability)
2. Update exposure max to 4004
3. Accept frame rate drop to 10 FPS
4. **Expected gain:** 3x brightness improvement
5. **Risk:** LOW - this is a standard technique

### Phase 2: Digital Gain Override (MEDIUM RISK)
1. After applying max exposure (4004), check if still too dark
2. If needed, boost digital gain registers beyond LUT:
   - Try 0x020c=0x06, 0x020d=0x00 (1.5x beyond LUT max)
   - Then 0x020c=0x08, 0x020d=0x00 (2x beyond LUT max)
3. Monitor for noise/artifacts
4. **Expected gain:** 1.5-2x additional brightness
5. **Risk:** MEDIUM - may introduce noise

### Phase 3: Black Level Adjustment (EXPERIMENTAL)
1. Reduce black level registers:
   - 0x0030-0x0033: 0x80 → 0x60
   - 0x0070-0x0073: 0x40 → 0x20
2. **Expected gain:** 10-20% brightness lift
3. **Risk:** MEDIUM - may affect dynamic range

### Phase 4: Gamma Boost (LAST RESORT)
1. Increase gamma curve registers:
   - 0x00e0-0x00e7: 0x18 → 0x28
2. **Expected gain:** 20-30% perceived brightness
3. **Risk:** MEDIUM - may look artificial

---

## CONCRETE REGISTER VALUES TO TEST

### Test 1: Extended VTS (3x exposure)
```c
// In initialization array
{0x0220, 0x0f},  // VTS = 4005
{0x0221, 0xa5},
// In defines
#define GC2607_EXPOSURE_MAX  4004
```

### Test 2: Double Digital Gain (after max exposure)
```c
// After applying max analog gain (LUT index 16)
gc2607_write_reg(gc2607, 0x020c, 0x08);  // Double digital gain
gc2607_write_reg(gc2607, 0x020d, 0x00);
```

### Test 3: Reduced Black Level
```c
// In initialization array - replace existing values
{0x0030, 0x60},  // Was 0x80
{0x0031, 0x60},
{0x0032, 0x60},
{0x0033, 0x60},
{0x0070, 0x20},  // Was 0x40
{0x0071, 0x20},
{0x0072, 0x20},
{0x0073, 0x20},
```

### Test 4: Gamma Boost
```c
// In initialization array - replace existing values
{0x00e0, 0x28},  // Was 0x18
{0x00e1, 0x28},
{0x00e2, 0x28},
{0x00e3, 0x28},
{0x00e4, 0x28},
{0x00e5, 0x28},
{0x00e6, 0x28},
{0x00e7, 0x28},
```

---

## THEORETICAL MAXIMUM BRIGHTNESS GAIN

If all methods are combined:
- VTS extension: 3x brightness
- Digital gain boost: 2x brightness
- Black level reduction: 1.2x brightness
- Gamma boost: 1.3x brightness

**Total theoretical gain:** 3 × 2 × 1.2 × 1.3 = **9.36x brightness**

However, practical gain will be lower due to noise and saturation limits.

---

## PRIORITY ORDER FOR TESTING

1. **START HERE:** VTS extension to 4005 (safest, biggest gain)
2. If still dark: Digital gain override to 0x0800
3. If still dark: Reduce black level registers
4. If still dark: Gamma boost
5. Fine-tune all parameters together

