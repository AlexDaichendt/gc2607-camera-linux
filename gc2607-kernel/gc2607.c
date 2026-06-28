// SPDX-License-Identifier: GPL-2.0
/*
 * GalaxyCore GC2607 sensor driver
 *
 * 1/7.3" 1080p RAW10 Bayer sensor, 2-lane MIPI CSI-2, as wired on the
 * HUAWEI MateBook (Intel IPU6 / Meteor Lake, INT3472 PMIC, 19.2 MHz MCLK).
 * The register init set and blanking are tuned for a 19.2 MHz external clock.
 */

#include <linux/acpi.h>
#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/regulator/consumer.h>
#include <linux/regmap.h>
#include <media/v4l2-cci.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-event.h>
#include <media/v4l2-fwnode.h>
#include <media/v4l2-async.h>
#include <media/v4l2-common.h>

#define GC2607_CHIP_ID			0x2607
#define GC2607_REG_CHIP_ID_H		CCI_REG8(0x03f0)
#define GC2607_REG_CHIP_ID_L		CCI_REG8(0x03f1)

/* Exposure and gain registers (datasheet section 9.6 + register list) */
#define GC2607_REG_EXPOSURE_H		CCI_REG8(0x0202)	/* CISCTL_exp[14:8] */
#define GC2607_REG_EXPOSURE_L		CCI_REG8(0x0203)	/* CISCTL_exp[7:0] */
#define GC2607_REG_AGAIN_H		CCI_REG8(0x02b3)	/* ANALOG_PGA_gain_T1 */
#define GC2607_REG_AGAIN_L		CCI_REG8(0x02b4)
#define GC2607_REG_DGAIN_H		CCI_REG8(0x020c)	/* col_gain_T1 (analog fine-trim) */
#define GC2607_REG_DGAIN_L		CCI_REG8(0x020d)

/* Image orientation (datasheet §6.1 / CSI/PHY1.0 register list):
 * bit[1]=updown (VFLIP), bit[0]=mirror (HFLIP). Flipping shifts the Bayer
 * first-pixel: Normal=Gr, HFlip=R, VFlip=B, Both=Gb.
 */
#define GC2607_REG_ORIENTATION		CCI_REG8(0x0101)

#define GC2607_REG_FLL_H		CCI_REG8(0x0340)	/* frame_length[14:8] (documented) */
#define GC2607_REG_FLL_L		CCI_REG8(0x0341)
#define GC2607_REG_VTS_H		CCI_REG8(0x0220)	/* undocumented frame-length mirror */
#define GC2607_REG_VTS_L		CCI_REG8(0x0221)	/* (kept from the reference init) */
#define GC2607_REG_HTS_H		CCI_REG8(0x0342)	/* CISCTL_hb (line period) [11:8]; datasheet default 1200 */
#define GC2607_REG_HTS_L		CCI_REG8(0x0343)	/* CISCTL_hb [7:0]; tuned to 1959 for 30fps@19.2MHz */

/* Page select / soft-reset (write 0xf0 to reset, 0x00 to select page 0) */
#define GC2607_REG_PAGE_SELECT		CCI_REG8(0x03fe)

/* External clock the shipped init/timing assumes. The sensor itself accepts
 * 6..27 MHz (datasheet typ 24 MHz), but the PLL block in the init array only
 * yields 30 fps at this rate; any other rate moves the pixel clock.
 */
#define GC2607_XCLK_FREQ		19200000

#define GC2607_DATA_LANES		2

/* Exposure and gain limits */
#define GC2607_EXPOSURE_MIN		4
#define GC2607_EXPOSURE_MAX		(GC2607_VTS - GC2607_EXPOSURE_MARGIN)  /* tracks frame length */
#define GC2607_EXPOSURE_STEP		1
#define GC2607_EXPOSURE_DEFAULT		1000	/* indoor default, < VTS */

/* Analog gain: V4L2_CID_ANALOGUE_GAIN is in 1/64 units to match the IPU6
 * tuning (gc2607_gc2607_MTL.aiqb). Its CMC describes analog gain as
 * real_gain = code / 64 (SMIA M0=1 C0=0 M1=0 C1=64), so the AIQ always emits
 * codes >= 64. The again table below realizes discrete steps from 1.0x
 * (code 64) up to 15.8125x (code 1012) via regs 0x02b3/0x02b4 plus the
 * 0x020c/0x020d fine-trim; s_ctrl selects the highest entry whose code does
 * not exceed the requested value.
 */
#define GC2607_ANA_GAIN_MIN		64	/* 1.0x (64/64) */
#define GC2607_ANA_GAIN_MAX		1012	/* 15.8125x = again-LUT ceiling */
#define GC2607_ANA_GAIN_STEP		1
#define GC2607_ANA_GAIN_DEFAULT		64	/* 1.0x; AE raises it as needed */

/* Sensor timing. The init register set keeps the reference (24 MHz) PLL but
 * runs near-minimum blanking so that at this board's 19.2 MHz MCLK the
 * resulting ~65.6 MHz readout clock still yields 30 fps. See README / FINDINGS.
 */
#define GC2607_HTS			1959	/* line length 0x0342/0x0343 */
#define GC2607_VTS			1116	/* min frame length (1080+20+16) -> 30.0 fps */
#define GC2607_WIDTH			1920
#define GC2607_HEIGHT			1080
#define GC2607_HBLANK			(GC2607_HTS - GC2607_WIDTH)   /* 39, llp=width+hblank */
#define GC2607_VBLANK			(GC2607_VTS - GC2607_HEIGHT)  /* 36, fll=height+vblank (30fps) */
#define GC2607_VBLANK_MAX		2270	/* VTS up to ~3350 -> ~10fps for low-light AE */
#define GC2607_EXPOSURE_MARGIN		8	/* exposure must stay below frame length */

/* Sensor readout pixel rate = HTS x VTS x fps. The HAL 3A uses it together with
 * hblank/vblank for frame-duration and exposure<->time conversion, so it must
 * be the readout rate, NOT the MIPI bus rate.
 */
#define GC2607_PIXEL_RATE		((s64)GC2607_HTS * GC2607_VTS * 30)  /* ~65.6 MHz */
#define GC2607_LINK_FREQ		336000000LL  /* 672 Mbps / 2 lanes */

/* Gain lookup table entry. The again pipeline uses four registers together
 * (0x02b3/0x02b4 analog stage + 0x020c/0x020d digital fine-trim); 'code' is the
 * realized analog gain in 1/64 units (= real_gain * 64), matching the units the
 * IPU6 AIQ writes to V4L2_CID_ANALOGUE_GAIN.
 */
struct gc2607_gain_lut {
	u8 reg2b3;
	u8 reg2b4;
	u8 reg20c;
	u8 reg20d;
	u16 code;
};

/* Register combinations from the GalaxyCore reference again table. The 'code'
 * column is the original real-gain figure expressed in 1/64 units, so the table
 * is indexed by the AIQ's analog_gain_code_global rather than a 0-16 index.
 */
static const struct gc2607_gain_lut gc2607_gain_table[] = {
	{0x00, 0x00, 0x00, 0x40,   64},  /* 1.0000x */
	{0x05, 0x00, 0x00, 0x4b,   76},  /* 1.1875x */
	{0x00, 0x01, 0x00, 0x59,   93},  /* 1.4531x */
	{0x05, 0x01, 0x00, 0x6a,  111},  /* 1.7344x */
	{0x00, 0x02, 0x00, 0x80,  130},  /* 2.0313x */
	{0x05, 0x02, 0x00, 0x97,  156},  /* 2.4375x */
	{0x00, 0x03, 0x00, 0xb3,  184},  /* 2.8750x */
	{0x05, 0x03, 0x00, 0xd4,  221},  /* 3.4531x */
	{0x00, 0x04, 0x01, 0x00,  253},  /* 3.9531x */
	{0x05, 0x04, 0x01, 0x2f,  304},  /* 4.7500x */
	{0x00, 0x05, 0x01, 0x66,  367},  /* 5.7344x */
	{0x05, 0x05, 0x01, 0xa8,  434},  /* 6.7813x */
	{0x00, 0x06, 0x02, 0x00,  510},  /* 7.9688x */
	{0x05, 0x06, 0x02, 0x5e,  607},  /* 9.4844x */
	{0x09, 0x26, 0x02, 0xcc,  717},  /* 11.2031x */
	{0x0c, 0xb6, 0x03, 0x50,  847},  /* 13.2344x */
	{0x10, 0x06, 0x04, 0x00, 1012},  /* 15.8125x - highest gain */
};

#define GC2607_GAIN_TABLE_SIZE ARRAY_SIZE(gc2607_gain_table)

/* Map a requested analog gain code (1/64 units) to the highest again table
 * entry whose realized gain does not exceed it (SMIA-style round-down, matching
 * the GalaxyCore reference alloc_again). Codes below the first entry clamp to
 * 1.0x; the control range already bounds the upper end.
 */
static const struct gc2607_gain_lut *gc2607_again_for_code(u32 code)
{
	int i;

	for (i = GC2607_GAIN_TABLE_SIZE - 1; i >= 0; i--)
		if (code >= gc2607_gain_table[i].code)
			return &gc2607_gain_table[i];

	return &gc2607_gain_table[0];
}

/* Sensor mode structure */
struct gc2607_mode {
	u32 width;
	u32 height;
	u32 hts;
	u32 vts;
	u32 max_fps;
	u32 num_regs;
	const struct cci_reg_sequence *reg_list;
};

struct gc2607 {
	struct v4l2_subdev sd;
	struct media_pad pad;
	struct i2c_client *client;
	struct regmap *regmap;

	/* Serializes s_stream against control writes (also the ctrl handler lock) */
	struct mutex mutex;

	/* V4L2 controls */
	struct v4l2_ctrl_handler ctrls;
	struct v4l2_ctrl *link_freq;
	struct v4l2_ctrl *pixel_rate;
	struct v4l2_ctrl *exposure;
	struct v4l2_ctrl *analogue_gain;
	struct v4l2_ctrl *hflip;
	struct v4l2_ctrl *vflip;
	struct v4l2_ctrl *vblank;

	/* Power management resources (provided by INT3472 PMIC) */
	struct clk *xclk;		/* Master clock (19.2 MHz on this board) */
	struct gpio_desc *reset_gpio;	/* Reset GPIO (active low) */
	struct gpio_desc *powerdown_gpio; /* Power-down GPIO (if present) */
	struct regulator_bulk_data supplies[3];

	/* Current mode */
	const struct gc2607_mode *cur_mode;

	/* Device state */
	bool streaming;
};

static inline struct gc2607 *to_gc2607(struct v4l2_subdev *sd)
{
	return container_of(sd, struct gc2607, sd);
}

/*
 * Register initialization sequence for 1920x1080@30fps MIPI mode.
 * Derived from the GalaxyCore reference init, with blanking retuned for 30 fps
 * at this board's 19.2 MHz MCLK (see README / FINDINGS).
 */
static const struct cci_reg_sequence gc2607_1080p_30fps_regs[] = {
	/* Soft reset: two 0xf0 pulses select and reset the chip, then four 0x00
	 * writes confirm page 0 selection.
	 */
	{ GC2607_REG_PAGE_SELECT, 0xf0 },
	{ GC2607_REG_PAGE_SELECT, 0xf0 },
	{ GC2607_REG_PAGE_SELECT, 0x00 },
	{ GC2607_REG_PAGE_SELECT, 0x00 },
	{ GC2607_REG_PAGE_SELECT, 0x00 },
	{ GC2607_REG_PAGE_SELECT, 0x00 },

	/* PLL and clock configuration */
	{ CCI_REG8(0x0d06), 0x01 },
	{ CCI_REG8(0x0315), 0xd4 },  /* PLL pre-divider */
	{ CCI_REG8(0x0d82), 0x14 },
	{ CCI_REG8(0x0a70), 0x80 },
	{ CCI_REG8(0x0134), 0x5b },
	{ CCI_REG8(0x0110), 0x01 },
	{ CCI_REG8(0x0dd1), 0x56 },
	{ CCI_REG8(0x0137), 0x03 },
	{ CCI_REG8(0x0135), 0x01 },
	{ CCI_REG8(0x0136), 0x2a },
	{ CCI_REG8(0x0130), 0x08 },
	{ CCI_REG8(0x0132), 0x01 },
	{ CCI_REG8(0x031c), 0x93 },

	/* Frame timing: FLL (documented), HTS, VTS (undocumented mirror) */
	{ CCI_REG8(0x0218), 0x00 },
	{ GC2607_REG_FLL_H, 0x04 },   /* frame length 0x045c = 1116 */
	{ GC2607_REG_FLL_L, 0x5c },
	{ GC2607_REG_HTS_H, 0x07 },   /* HTS 0x07a7 = 1959 (tight h-blank for 30fps) */
	{ GC2607_REG_HTS_L, 0xa7 },
	{ GC2607_REG_VTS_H, 0x04 },   /* VTS 0x045c = 1116 -> 30.0 fps */
	{ GC2607_REG_VTS_L, 0x5c },

	/* Output format and windowing */
	{ CCI_REG8(0x0af4), 0x2b },
	{ CCI_REG8(0x0002), 0x30 },
	{ CCI_REG8(0x00c3), 0x3c },
	{ CCI_REG8(0x0101), 0x00 },  /* Image_Orientation: [1]=updown [0]=mirror; 0x00=normal */
	{ CCI_REG8(0x0d05), 0xcc },
	{ CCI_REG8(0x0218), 0x00 },  /* second write from reference; purpose unclear, kept for safety */
	{ CCI_REG8(0x005e), 0x84 },
	{ CCI_REG8(0x0007), 0x15 },
	{ CCI_REG8(0x0350), 0x01 },
	{ CCI_REG8(0x00c0), 0x07 },  /* CISCTL_win_width H: total readout width = 1936 (1920 + 8+8 dummy cols) */
	{ CCI_REG8(0x00c1), 0x90 },  /* CISCTL_win_width L */
	{ CCI_REG8(0x0346), 0x00 },  /* CISCTL_row_start H: first active column [10:8] */
	{ CCI_REG8(0x0347), 0x02 },  /* CISCTL_row_start L: col_start = 2 (skip 2 dummy columns) */
	{ CCI_REG8(0x034a), 0x04 },  /* CISCTL_win_height H: window height = 1088 (1080 + 8 dummy rows) */
	{ CCI_REG8(0x034b), 0x40 },  /* CISCTL_win_height L */
	{ CCI_REG8(0x021f), 0x12 },  /* output format control */
	{ CCI_REG8(0x034c), 0x07 },  /* output width H (0x0780 = 1920; undocumented in brief) */
	{ CCI_REG8(0x034d), 0x80 },  /* output width L */
	{ CCI_REG8(0x0353), 0x00 },  /* column offset H (undocumented) */
	{ CCI_REG8(0x0354), 0x04 },  /* column offset L */

	/* Sensor analog timing */
	{ CCI_REG8(0x0d11), 0x10 },
	/* 0x0d22 is written 0x00 here to reset the ISP block, then 0x38 below
	 * after the analog timing registers have been configured.
	 */
	{ CCI_REG8(0x0d22), 0x00 },
	{ CCI_REG8(0x03f6), 0x4d },  /* PLL post-divider */
	{ CCI_REG8(0x03f5), 0x3c },
	{ CCI_REG8(0x03f3), 0x54 },
	{ CCI_REG8(0x0d07), 0xdd },
	{ CCI_REG8(0x0e71), 0x00 },
	{ CCI_REG8(0x0e72), 0x10 },
	{ CCI_REG8(0x0e17), 0x26 },
	{ CCI_REG8(0x0e22), 0x0d },
	{ CCI_REG8(0x0e23), 0x20 },
	{ CCI_REG8(0x0e1b), 0x30 },
	{ CCI_REG8(0x0e3a), 0x15 },
	{ CCI_REG8(0x0e0a), 0x00 },
	{ CCI_REG8(0x0e0b), 0x00 },
	{ CCI_REG8(0x0e0e), 0x00 },
	{ CCI_REG8(0x0e2a), 0x08 },
	{ CCI_REG8(0x0e2b), 0x08 },

	/* ISP control */
	{ CCI_REG8(0x0d02), 0x73 },
	{ CCI_REG8(0x0d22), 0x38 },  /* ISP enable flags (final value) */
	{ CCI_REG8(0x0d25), 0x00 },
	{ CCI_REG8(0x0e6a), 0x39 },

	/* Initial gain and AWB coefficients */
	{ CCI_REG8(0x0050), 0x05 },
	{ CCI_REG8(0x0089), 0x03 },
	{ CCI_REG8(0x0070), 0x40 },  /* Gr digital gain */
	{ CCI_REG8(0x0071), 0x40 },  /* R digital gain */
	{ CCI_REG8(0x0072), 0x40 },  /* B digital gain */
	{ CCI_REG8(0x0073), 0x40 },  /* Gb digital gain */
	{ CCI_REG8(0x0040), 0x82 },
	{ CCI_REG8(0x0030), 0x80 },  /* global Gr gain */
	{ CCI_REG8(0x0031), 0x80 },  /* global R gain */
	{ CCI_REG8(0x0032), 0x80 },  /* global B gain */
	{ CCI_REG8(0x0033), 0x80 },  /* global Gb gain */
	{ GC2607_REG_EXPOSURE_H, 0x04 },  /* CISCTL_exp: default exposure 0x0438 = 1080 lines */
	{ GC2607_REG_EXPOSURE_L, 0x38 },
	{ GC2607_REG_AGAIN_H, 0x00 },     /* ANALOG_PGA_gain_T1: analog gain = 1.0x */
	{ GC2607_REG_AGAIN_H, 0x00 },     /* second write from reference; purpose unclear, kept for safety */
	{ GC2607_REG_AGAIN_L, 0x00 },
	{ CCI_REG8(0x0208), 0x04 },  /* auto_pregain_T1 H (pre-gain for T1 exposure) */
	{ CCI_REG8(0x0209), 0x00 },  /* auto_pregain_T1 L */
	{ CCI_REG8(0x009e), 0x01 },
	{ CCI_REG8(0x009f), 0xa0 },

	/* MIPI Tx timing (clock lane: §8.1, data lane: §8.2) */
	{ CCI_REG8(0x0db8), 0x08 },  /* T_CLK_POST */
	{ CCI_REG8(0x0db6), 0x02 },  /* T_CLK_PRE */
	{ CCI_REG8(0x0db4), 0x05 },  /* T_CLK_HS_PREPARE */
	{ CCI_REG8(0x0db5), 0x16 },  /* T_CLK_ZERO */
	{ CCI_REG8(0x0db9), 0x09 },  /* T_CLK_TRAIL */
	{ CCI_REG8(0x0d93), 0x05 },  /* T_LPX */
	{ CCI_REG8(0x0d94), 0x06 },  /* T_HS_PREPARE */
	{ CCI_REG8(0x0d95), 0x0b },  /* T_HS_ZERO */
	{ CCI_REG8(0x0d99), 0x10 },  /* T_HS_TRAIL */

	/* MIPI control: two-phase enable — 0x01 arms the Tx, then PLL registers
	 * are configured, then 0x91 enables clock and data lanes.
	 */
	{ CCI_REG8(0x0082), 0x03 },
	{ CCI_REG8(0x0107), 0x05 },  /* CSI2_mode2: mode_update=1, mipi_wclk_gate_en=1 */
	{ CCI_REG8(0x0117), 0x01 },  /* MIPI Tx enable phase 1 */
	{ CCI_REG8(0x0d80), 0x07 },
	{ CCI_REG8(0x0d81), 0x02 },
	{ CCI_REG8(0x0d84), 0x09 },
	{ CCI_REG8(0x0d85), 0x60 },
	{ CCI_REG8(0x0d86), 0x04 },
	{ CCI_REG8(0x0d87), 0xb1 },
	{ CCI_REG8(0x0222), 0x00 },
	{ CCI_REG8(0x0223), 0x01 },
	{ CCI_REG8(0x0117), 0x91 },  /* MIPI Tx enable phase 2 (clk + data lanes) */

	/* Analog calibration */
	{ CCI_REG8(0x03f4), 0x38 },
	{ CCI_REG8(0x0e69), 0x00 },
	{ CCI_REG8(0x00d6), 0x00 },
	{ CCI_REG8(0x00d0), 0x0d },
	{ CCI_REG8(0x00e0), 0x18 },  /* per-channel calibration [0..7] */
	{ CCI_REG8(0x00e1), 0x18 },
	{ CCI_REG8(0x00e2), 0x18 },
	{ CCI_REG8(0x00e3), 0x18 },
	{ CCI_REG8(0x00e4), 0x18 },
	{ CCI_REG8(0x00e5), 0x18 },
	{ CCI_REG8(0x00e6), 0x18 },
	{ CCI_REG8(0x00e7), 0x18 },
};

/* Supported sensor modes */
static const struct gc2607_mode gc2607_modes[] = {
	{
		.width = GC2607_WIDTH,
		.height = GC2607_HEIGHT,
		.hts = GC2607_HTS,
		.vts = GC2607_VTS,
		.max_fps = 30,
		.num_regs = ARRAY_SIZE(gc2607_1080p_30fps_regs),
		.reg_list = gc2607_1080p_30fps_regs,
	},
};

/* Link frequency menu items */
static const s64 gc2607_link_freqs[] = {
	GC2607_LINK_FREQ,
};

/*
 * Bayer first-pixel shifts with flip (datasheet §6.1):
 *   normal → Gr (SGRBG), hflip → R (SRGGB), vflip → B (SBGGR), both → Gb (SGBRG).
 */
static u32 gc2607_mbus_code(bool hflip, bool vflip)
{
	if (!hflip && !vflip)
		return MEDIA_BUS_FMT_SGRBG10_1X10;
	if (hflip && !vflip)
		return MEDIA_BUS_FMT_SRGGB10_1X10;
	if (!hflip && vflip)
		return MEDIA_BUS_FMT_SBGGR10_1X10;
	return MEDIA_BUS_FMT_SGBRG10_1X10;
}

static void gc2607_fill_fmt(const struct gc2607_mode *mode,
			    struct v4l2_mbus_framefmt *fmt,
			    bool hflip, bool vflip)
{
	fmt->width = mode->width;
	fmt->height = mode->height;
	fmt->code = gc2607_mbus_code(hflip, vflip);
	fmt->field = V4L2_FIELD_NONE;
	fmt->colorspace = V4L2_COLORSPACE_RAW;
}

/*
 * Power management
 */
static int gc2607_power_on(struct gc2607 *gc2607)
{
	struct i2c_client *client = gc2607->client;
	int ret;

	/* Enable regulators if available */
	if (gc2607->supplies[0].supply) {
		ret = regulator_bulk_enable(ARRAY_SIZE(gc2607->supplies),
					    gc2607->supplies);
		if (ret) {
			dev_err(&client->dev, "Failed to enable regulators: %d\n", ret);
			return ret;
		}
		usleep_range(5000, 6000);
	}

	ret = clk_prepare_enable(gc2607->xclk);
	if (ret) {
		dev_err(&client->dev, "Failed to enable clock: %d\n", ret);
		goto err_reg;
	}
	usleep_range(5000, 6000);

	/*
	 * Reset sequence from the Windows reference driver, validated on
	 * hardware: assert RESETB (LOW) for 20 ms, then de-assert (HIGH) with
	 * a 10 ms settle.  The preliminary datasheet (§9.2, V0.1) lists all
	 * power-on timing parameters as TBD, so these conservative values are
	 * the best available reference.
	 *
	 * The GPIO is described active-low: gpiod_set_value(1) asserts
	 * (physical LOW = reset), gpiod_set_value(0) de-asserts (HIGH = run).
	 */
	if (gc2607->reset_gpio) {
		gpiod_set_value_cansleep(gc2607->reset_gpio, 0);
		msleep(20);
		gpiod_set_value_cansleep(gc2607->reset_gpio, 1);
		msleep(20);
		gpiod_set_value_cansleep(gc2607->reset_gpio, 0);
		msleep(10);
	}

	/* If present, pulse the powerdown GPIO (active high: 1 = powered down) */
	if (gc2607->powerdown_gpio) {
		gpiod_set_value_cansleep(gc2607->powerdown_gpio, 1);
		msleep(10);
		gpiod_set_value_cansleep(gc2607->powerdown_gpio, 0);
		msleep(10);
	}

	/* Wait for sensor to fully boot */
	msleep(20);

	dev_dbg(&client->dev, "Sensor powered on\n");

	return 0;

err_reg:
	clk_disable_unprepare(gc2607->xclk);
	if (gc2607->supplies[0].supply)
		regulator_bulk_disable(ARRAY_SIZE(gc2607->supplies), gc2607->supplies);
	return ret;
}

static void gc2607_power_off(struct gc2607 *gc2607)
{
	struct i2c_client *client = gc2607->client;

	if (gc2607->reset_gpio)
		gpiod_set_value_cansleep(gc2607->reset_gpio, 0);

	if (gc2607->powerdown_gpio)
		gpiod_set_value_cansleep(gc2607->powerdown_gpio, 1);

	clk_disable_unprepare(gc2607->xclk);

	if (gc2607->supplies[0].supply)
		regulator_bulk_disable(ARRAY_SIZE(gc2607->supplies), gc2607->supplies);

	dev_dbg(&client->dev, "Sensor powered off\n");
}

/*
 * V4L2 subdev internal ops
 */
static int gc2607_init_state(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *sd_state)
{
	struct v4l2_mbus_framefmt *fmt =
		v4l2_subdev_state_get_format(sd_state, 0);

	gc2607_fill_fmt(&gc2607_modes[0], fmt, false, false);
	return 0;
}

static const struct v4l2_subdev_internal_ops gc2607_internal_ops = {
	.init_state = gc2607_init_state,
};

/*
 * V4L2 subdev pad operations
 */
static int gc2607_enum_mbus_code(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *sd_state,
				 struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index > 0)
		return -EINVAL;

	code->code = MEDIA_BUS_FMT_SGRBG10_1X10;
	return 0;
}

static int gc2607_enum_frame_size(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *sd_state,
				  struct v4l2_subdev_frame_size_enum *fse)
{
	if (fse->index >= ARRAY_SIZE(gc2607_modes))
		return -EINVAL;

	if (fse->code != MEDIA_BUS_FMT_SGRBG10_1X10)
		return -EINVAL;

	fse->min_width = gc2607_modes[fse->index].width;
	fse->max_width = gc2607_modes[fse->index].width;
	fse->min_height = gc2607_modes[fse->index].height;
	fse->max_height = gc2607_modes[fse->index].height;

	return 0;
}

static int gc2607_enum_frame_interval(struct v4l2_subdev *sd,
				      struct v4l2_subdev_state *sd_state,
				      struct v4l2_subdev_frame_interval_enum *fie)
{
	if (fie->index >= ARRAY_SIZE(gc2607_modes))
		return -EINVAL;

	if (fie->code != MEDIA_BUS_FMT_SGRBG10_1X10)
		return -EINVAL;

	if (fie->width != gc2607_modes[fie->index].width ||
	    fie->height != gc2607_modes[fie->index].height)
		return -EINVAL;

	fie->interval.numerator = 1;
	fie->interval.denominator = gc2607_modes[fie->index].max_fps;

	return 0;
}

static int gc2607_get_frame_interval(struct v4l2_subdev *sd,
				     struct v4l2_subdev_state *sd_state,
				     struct v4l2_subdev_frame_interval *fi)
{
	struct gc2607 *gc2607 = to_gc2607(sd);

	if (fi->which != V4L2_SUBDEV_FORMAT_ACTIVE)
		return -EINVAL;

	fi->interval.numerator = 1;
	fi->interval.denominator = gc2607->cur_mode->max_fps;

	return 0;
}

static int gc2607_get_fmt(struct v4l2_subdev *sd,
			  struct v4l2_subdev_state *sd_state,
			  struct v4l2_subdev_format *format)
{
	struct gc2607 *gc2607 = to_gc2607(sd);

	if (format->which == V4L2_SUBDEV_FORMAT_ACTIVE) {
		gc2607_fill_fmt(gc2607->cur_mode, &format->format,
				gc2607->hflip->val, gc2607->vflip->val);
	} else {
		format->format = *v4l2_subdev_state_get_format(sd_state,
							       format->pad);
	}
	return 0;
}

static int gc2607_set_fmt(struct v4l2_subdev *sd,
			  struct v4l2_subdev_state *sd_state,
			  struct v4l2_subdev_format *format)
{
	struct gc2607 *gc2607 = to_gc2607(sd);
	struct v4l2_mbus_framefmt *fmt;

	/* Only 10-bit Bayer is supported (exact code depends on flip state). */
	switch (format->format.code) {
	case MEDIA_BUS_FMT_SGRBG10_1X10:
	case MEDIA_BUS_FMT_SRGGB10_1X10:
	case MEDIA_BUS_FMT_SBGGR10_1X10:
	case MEDIA_BUS_FMT_SGBRG10_1X10:
		break;
	default:
		return -EINVAL;
	}

	fmt = v4l2_subdev_state_get_format(sd_state, format->pad);

	/* Single fixed mode: fill with the flip-derived code and fixed size. */
	gc2607_fill_fmt(&gc2607_modes[0], fmt,
			gc2607->hflip->val, gc2607->vflip->val);
	format->format = *fmt;

	if (format->which == V4L2_SUBDEV_FORMAT_ACTIVE)
		gc2607->cur_mode = &gc2607_modes[0];

	return 0;
}

static const struct v4l2_subdev_pad_ops gc2607_pad_ops = {
	.enum_mbus_code = gc2607_enum_mbus_code,
	.enum_frame_size = gc2607_enum_frame_size,
	.enum_frame_interval = gc2607_enum_frame_interval,
	.get_frame_interval = gc2607_get_frame_interval,
	.set_frame_interval = gc2607_get_frame_interval,
	.get_fmt = gc2607_get_fmt,
	.set_fmt = gc2607_set_fmt,
};

/*
 * V4L2 subdev video operations
 */
static int gc2607_s_stream(struct v4l2_subdev *sd, int enable)
{
	struct gc2607 *gc2607 = to_gc2607(sd);
	struct i2c_client *client = gc2607->client;
	int ret = 0;

	mutex_lock(&gc2607->mutex);

	if (gc2607->streaming == enable)
		goto unlock;

	if (enable) {
		ret = pm_runtime_resume_and_get(&client->dev);
		if (ret)
			goto unlock;

		/*
		 * The GC2607 has no separate stream/standby register: streaming
		 * begins once the init sequence (PLL + clock enable) has been
		 * written, and stops when the sensor is powered down. So upload
		 * the mode and apply the current controls here.
		 */
		ret = cci_multi_reg_write(gc2607->regmap, gc2607->cur_mode->reg_list,
					  gc2607->cur_mode->num_regs, NULL);
		if (ret) {
			dev_err(&client->dev, "Failed to initialize sensor: %d\n", ret);
			goto err_pm;
		}

		ret = __v4l2_ctrl_handler_setup(&gc2607->ctrls);
		if (ret) {
			dev_err(&client->dev, "Failed to apply controls: %d\n", ret);
			goto err_pm;
		}

		gc2607->streaming = true;
	} else {
		gc2607->streaming = false;
		pm_runtime_put(&client->dev);
	}

	mutex_unlock(&gc2607->mutex);
	return 0;

err_pm:
	pm_runtime_put(&client->dev);
unlock:
	mutex_unlock(&gc2607->mutex);
	return ret;
}

/*
 * V4L2 control operations
 */
static int gc2607_s_ctrl(struct v4l2_ctrl *ctrl)
{
	struct gc2607 *gc2607 = container_of(ctrl->handler,
					     struct gc2607, ctrls);
	struct i2c_client *client = gc2607->client;
	int ret = 0;

	/* VBLANK changes the frame length, which sets the exposure ceiling.
	 * Retrack the exposure control's max before touching hardware.
	 */
	if (ctrl->id == V4L2_CID_VBLANK) {
		int vts = GC2607_HEIGHT + ctrl->val;

		__v4l2_ctrl_modify_range(gc2607->exposure, GC2607_EXPOSURE_MIN,
					 vts - GC2607_EXPOSURE_MARGIN, 1,
					 gc2607->exposure->cur.val);
	}

	/* Only touch hardware while the sensor is powered/streaming. */
	if (!pm_runtime_get_if_in_use(&client->dev))
		return 0;

	switch (ctrl->id) {
	case V4L2_CID_VBLANK: {
		int vts = GC2607_HEIGHT + ctrl->val;

		/* frame length lives in the documented 0x0340/41 plus the
		 * reference's 0x0220/21 mirror.
		 */
		ret = cci_write(gc2607->regmap, GC2607_REG_VTS_H,
				(vts >> 8) & 0x3f, NULL);
		if (!ret)
			ret = cci_write(gc2607->regmap, GC2607_REG_VTS_L,
					vts & 0xff, NULL);
		if (!ret)
			ret = cci_write(gc2607->regmap, GC2607_REG_FLL_H,
					(vts >> 8) & 0x7f, NULL);
		if (!ret)
			ret = cci_write(gc2607->regmap, GC2607_REG_FLL_L,
					vts & 0xff, NULL);
		break;
	}

	case V4L2_CID_EXPOSURE:
		/* 15-bit shutter time, high byte is CISCTL_exp[14:8]. */
		ret = cci_write(gc2607->regmap, GC2607_REG_EXPOSURE_H,
				(ctrl->val >> 8) & 0x7f, NULL);
		if (!ret)
			ret = cci_write(gc2607->regmap, GC2607_REG_EXPOSURE_L,
					ctrl->val & 0xff, NULL);
		break;

	case V4L2_CID_ANALOGUE_GAIN: {
		/* ctrl->val is an analog gain code in 1/64 units (real_gain * 64),
		 * as produced by the IPU6 AIQ. Round down to the nearest realizable
		 * again table entry and program its four registers.
		 */
		const struct gc2607_gain_lut *lut = gc2607_again_for_code(ctrl->val);

		ret = cci_write(gc2607->regmap, GC2607_REG_AGAIN_H,
				lut->reg2b3, NULL);
		if (!ret)
			ret = cci_write(gc2607->regmap, GC2607_REG_AGAIN_L,
					lut->reg2b4, NULL);
		if (!ret)
			ret = cci_write(gc2607->regmap, GC2607_REG_DGAIN_H,
					lut->reg20c, NULL);
		if (!ret)
			ret = cci_write(gc2607->regmap, GC2607_REG_DGAIN_L,
					lut->reg20d, NULL);
		break;
	}

	case V4L2_CID_HFLIP:
	case V4L2_CID_VFLIP: {
		/* Both controls map to the same register; write both bits together.
		 * bit[0]=mirror (HFLIP), bit[1]=updown (VFLIP) — datasheet §6.1.
		 */
		u8 orientation = 0;

		if (gc2607->hflip->val)
			orientation |= BIT(0);
		if (gc2607->vflip->val)
			orientation |= BIT(1);
		ret = cci_write(gc2607->regmap, GC2607_REG_ORIENTATION,
				orientation, NULL);
		break;
	}

	default:
		ret = -EINVAL;
		break;
	}

	pm_runtime_put(&client->dev);
	return ret;
}

static const struct v4l2_ctrl_ops gc2607_ctrl_ops = {
	.s_ctrl = gc2607_s_ctrl,
};

static const struct v4l2_subdev_core_ops gc2607_core_ops = {
	.log_status = v4l2_ctrl_subdev_log_status,
	.subscribe_event = v4l2_ctrl_subdev_subscribe_event,
	.unsubscribe_event = v4l2_event_subdev_unsubscribe,
};

static const struct v4l2_subdev_video_ops gc2607_video_ops = {
	.s_stream = gc2607_s_stream,
};

static const struct v4l2_subdev_ops gc2607_subdev_ops = {
	.core = &gc2607_core_ops,
	.video = &gc2607_video_ops,
	.pad = &gc2607_pad_ops,
};

/*
 * Detect chip ID to verify sensor presence
 */
static int gc2607_detect(struct gc2607 *gc2607)
{
	struct i2c_client *client = gc2607->client;
	u64 chip_id_h = 0, chip_id_l = 0;
	u16 chip_id;
	int ret;

	ret = cci_read(gc2607->regmap, GC2607_REG_CHIP_ID_H, &chip_id_h,
		       NULL);
	if (ret)
		return ret;

	ret = cci_read(gc2607->regmap, GC2607_REG_CHIP_ID_L, &chip_id_l,
		       NULL);
	if (ret)
		return ret;

	chip_id = (chip_id_h << 8) | chip_id_l;
	if (chip_id != GC2607_CHIP_ID) {
		dev_err(&client->dev, "Wrong chip ID: expected 0x%04x, got 0x%08llx %08llx\n",
			GC2607_CHIP_ID, chip_id_h, chip_id_l);
		return -ENODEV;
	}

	dev_dbg(&client->dev, "GC2607 chip detected (0x%04x)\n", chip_id);
	return 0;
}

/*
 * Runtime PM operations
 */
static int gc2607_runtime_suspend(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct gc2607 *gc2607 = to_gc2607(sd);

	gc2607_power_off(gc2607);
	return 0;
}

static int gc2607_runtime_resume(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct gc2607 *gc2607 = to_gc2607(sd);

	return gc2607_power_on(gc2607);
}

static DEFINE_RUNTIME_DEV_PM_OPS(gc2607_pm_ops, gc2607_runtime_suspend,
				  gc2607_runtime_resume, NULL);

/*
 * Validate the firmware-described hardware configuration: external clock rate,
 * number of MIPI data lanes, and that the firmware advertises our link freq.
 */
static int gc2607_check_hwcfg(struct device *dev, struct gc2607 *gc2607)
{
	struct fwnode_handle *ep, *fwnode = dev_fwnode(dev);
	struct v4l2_fwnode_endpoint bus_cfg = {
		.bus_type = V4L2_MBUS_CSI2_DPHY,
	};
	unsigned long link_freq_bitmap;
	u32 xclk_freq;
	int ret;

	if (!fwnode)
		return -ENXIO;

	xclk_freq = clk_get_rate(gc2607->xclk);
	if (xclk_freq != GC2607_XCLK_FREQ)
		return dev_err_probe(dev, -EINVAL,
				     "external clock %u Hz, expected %u Hz\n",
				     xclk_freq, GC2607_XCLK_FREQ);

	ep = fwnode_graph_get_next_endpoint(fwnode, NULL);
	if (!ep)
		return dev_err_probe(dev, -EPROBE_DEFER, "no endpoint found\n");

	ret = v4l2_fwnode_endpoint_alloc_parse(ep, &bus_cfg);
	fwnode_handle_put(ep);
	if (ret)
		return dev_err_probe(dev, ret, "failed to parse endpoint\n");

	if (bus_cfg.bus.mipi_csi2.num_data_lanes != GC2607_DATA_LANES) {
		ret = dev_err_probe(dev, -EINVAL, "got %u data lanes, expected %u\n",
				    bus_cfg.bus.mipi_csi2.num_data_lanes,
				    GC2607_DATA_LANES);
		goto out;
	}

	ret = v4l2_link_freq_to_bitmap(dev, bus_cfg.link_frequencies,
				       bus_cfg.nr_of_link_frequencies,
				       gc2607_link_freqs,
				       ARRAY_SIZE(gc2607_link_freqs),
				       &link_freq_bitmap);
out:
	v4l2_fwnode_endpoint_free(&bus_cfg);
	return ret;
}

static int gc2607_init_controls(struct gc2607 *gc2607)
{
	struct v4l2_ctrl_handler *hdl = &gc2607->ctrls;
	struct v4l2_ctrl *ctrl;
	int ret;

	ret = v4l2_ctrl_handler_init(hdl, 8);	/* link_freq, pixel_rate, hblank, vblank, exposure, analogue_gain, hflip, vflip */
	if (ret)
		return ret;

	/* Serialize control writes with s_stream via our own mutex. */
	hdl->lock = &gc2607->mutex;

	/* Link frequency (required by IPU6) */
	gc2607->link_freq = v4l2_ctrl_new_int_menu(hdl, NULL, V4L2_CID_LINK_FREQ,
						   ARRAY_SIZE(gc2607_link_freqs) - 1,
						   0, gc2607_link_freqs);
	if (gc2607->link_freq)
		gc2607->link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	/* Pixel rate (required by IPU6) */
	gc2607->pixel_rate = v4l2_ctrl_new_std(hdl, NULL, V4L2_CID_PIXEL_RATE,
					       GC2607_PIXEL_RATE, GC2607_PIXEL_RATE,
					       1, GC2607_PIXEL_RATE);
	if (gc2607->pixel_rate)
		gc2607->pixel_rate->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	/* HBLANK: read-only (line length is fixed for this mode -> llp). */
	ctrl = v4l2_ctrl_new_std(hdl, NULL, V4L2_CID_HBLANK,
				 GC2607_HBLANK, GC2607_HBLANK, 1, GC2607_HBLANK);
	if (ctrl)
		ctrl->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	/* VBLANK: writable so HAL 3A can extend the frame (lower fps) for longer
	 * exposure in low light -> less gain -> less noise. Drives VTS; exposure
	 * max tracks it (see gc2607_s_ctrl).
	 */
	gc2607->vblank = v4l2_ctrl_new_std(hdl, &gc2607_ctrl_ops, V4L2_CID_VBLANK,
					   GC2607_VBLANK, GC2607_VBLANK_MAX, 1,
					   GC2607_VBLANK);

	gc2607->exposure = v4l2_ctrl_new_std(hdl, &gc2607_ctrl_ops,
					     V4L2_CID_EXPOSURE,
					     GC2607_EXPOSURE_MIN, GC2607_EXPOSURE_MAX,
					     GC2607_EXPOSURE_STEP, GC2607_EXPOSURE_DEFAULT);

	/* Analog gain in 1/64 units (matches the .aiqb CMC) */
	gc2607->analogue_gain = v4l2_ctrl_new_std(hdl, &gc2607_ctrl_ops,
						  V4L2_CID_ANALOGUE_GAIN,
						  GC2607_ANA_GAIN_MIN, GC2607_ANA_GAIN_MAX,
						  GC2607_ANA_GAIN_STEP, GC2607_ANA_GAIN_DEFAULT);

	/* Flip controls: datasheet §6.1, register 0x0101 bits [1:0].
	 * Changing flip shifts the Bayer first-pixel; get_fmt reflects this.
	 */
	gc2607->hflip = v4l2_ctrl_new_std(hdl, &gc2607_ctrl_ops,
					  V4L2_CID_HFLIP, 0, 1, 1, 0);
	gc2607->vflip = v4l2_ctrl_new_std(hdl, &gc2607_ctrl_ops,
					  V4L2_CID_VFLIP, 0, 1, 1, 0);

	if (hdl->error) {
		ret = hdl->error;
		v4l2_ctrl_handler_free(hdl);
		return ret;
	}

	gc2607->sd.ctrl_handler = hdl;
	return 0;
}

/*
 * I2C driver probe/remove
 */
static int gc2607_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct gc2607 *gc2607;
	int ret;

	gc2607 = devm_kzalloc(dev, sizeof(*gc2607), GFP_KERNEL);
	if (!gc2607)
		return -ENOMEM;

	gc2607->client = client;
	gc2607->cur_mode = &gc2607_modes[0];
	mutex_init(&gc2607->mutex);

	/* CCI/regmap register access (16-bit addresses, 8-bit values) */
	gc2607->regmap = devm_cci_regmap_init_i2c(client, 16);
	if (IS_ERR(gc2607->regmap)) {
		ret = PTR_ERR(gc2607->regmap);
		dev_err(dev, "Failed to init CCI regmap: %d\n", ret);
		return ret;
	}

	/* Regulator supplies (optional - INT3472 may handle power internally) */
	gc2607->supplies[0].supply = "avdd";  /* Analog power */
	gc2607->supplies[1].supply = "dovdd"; /* I/O power */
	gc2607->supplies[2].supply = "dvdd";  /* Digital core power */

	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(gc2607->supplies),
				      gc2607->supplies);
	if (ret) {
		dev_dbg(dev, "Regulators not available (%d), assuming INT3472 handles power\n", ret);
		memset(gc2607->supplies, 0, sizeof(gc2607->supplies));
	}

	/* Reset GPIO (optional - INT3472 may drive it) */
	gc2607->reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(gc2607->reset_gpio)) {
		ret = PTR_ERR(gc2607->reset_gpio);
		goto err_mutex;
	}

	/* Powerdown GPIO (optional - active high: 1=powerdown, 0=running) */
	gc2607->powerdown_gpio = devm_gpiod_get_optional(dev, "powerdown",
							 GPIOD_OUT_LOW);
	if (IS_ERR(gc2607->powerdown_gpio)) {
		ret = PTR_ERR(gc2607->powerdown_gpio);
		goto err_mutex;
	}

	gc2607->xclk = devm_v4l2_sensor_clk_get(dev, NULL);
	if (IS_ERR(gc2607->xclk)) {
		ret = PTR_ERR(gc2607->xclk);
		goto err_mutex;
	}

	ret = gc2607_check_hwcfg(dev, gc2607);
	if (ret)
		goto err_mutex;

	/* Initialize V4L2 subdev */
	v4l2_i2c_subdev_init(&gc2607->sd, client, &gc2607_subdev_ops);
	gc2607->sd.internal_ops = &gc2607_internal_ops;
	gc2607->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE | V4L2_SUBDEV_FL_HAS_EVENTS;
	gc2607->sd.state_lock = &gc2607->mutex;

	ret = gc2607_init_controls(gc2607);
	if (ret) {
		dev_err(dev, "Failed to init controls: %d\n", ret);
		goto err_mutex;
	}

	/* Initialize media pad */
	gc2607->pad.flags = MEDIA_PAD_FL_SOURCE;
	gc2607->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;
	ret = media_entity_pads_init(&gc2607->sd.entity, 1, &gc2607->pad);
	if (ret) {
		dev_err(dev, "Failed to init media entity: %d\n", ret);
		goto err_ctrls;
	}

	ret = v4l2_subdev_init_finalize(&gc2607->sd);
	if (ret) {
		dev_err(dev, "Failed to finalize subdev: %d\n", ret);
		goto err_media;
	}

	/* Power on to detect chip ID, then release; sensor idles until streamed */
	pm_runtime_enable(dev);

	ret = pm_runtime_resume_and_get(dev);
	if (ret) {
		dev_err(dev, "Failed to power on sensor: %d\n", ret);
		goto err_pm;
	}

	ret = gc2607_detect(gc2607);
	if (ret) {
		dev_err(dev, "Failed to detect sensor: %d\n", ret);
		goto err_power;
	}

	ret = v4l2_async_register_subdev_sensor(&gc2607->sd);
	if (ret) {
		dev_err(dev, "Failed to register async subdev: %d\n", ret);
		goto err_power;
	}

	pm_runtime_put(dev);

	dev_info(dev, "GC2607 probed (SGRBG10 %ux%u@%ufps)\n",
		 gc2607->cur_mode->width, gc2607->cur_mode->height,
		 gc2607->cur_mode->max_fps);

	return 0;

err_power:
	pm_runtime_put_sync(dev);
err_pm:
	pm_runtime_disable(dev);
	pm_runtime_set_suspended(dev);
	v4l2_subdev_cleanup(&gc2607->sd);
err_media:
	media_entity_cleanup(&gc2607->sd.entity);
err_ctrls:
	v4l2_ctrl_handler_free(&gc2607->ctrls);
err_mutex:
	mutex_destroy(&gc2607->mutex);
	return ret;
}

static void gc2607_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct gc2607 *gc2607 = to_gc2607(sd);
	struct device *dev = &client->dev;

	v4l2_async_unregister_subdev(sd);
	v4l2_subdev_cleanup(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(&gc2607->ctrls);

	pm_runtime_disable(dev);
	if (!pm_runtime_status_suspended(dev))
		gc2607_power_off(gc2607);
	pm_runtime_set_suspended(dev);

	mutex_destroy(&gc2607->mutex);
}

static const struct acpi_device_id gc2607_acpi_ids[] = {
	{ "GCTI2607" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, gc2607_acpi_ids);

static const struct i2c_device_id gc2607_id[] = {
	{ "gc2607", 0 },
	{ }
};
MODULE_DEVICE_TABLE(i2c, gc2607_id);

static struct i2c_driver gc2607_i2c_driver = {
	.driver = {
		.name = "gc2607",
		.pm = pm_sleep_ptr(&gc2607_pm_ops),
		.acpi_match_table = gc2607_acpi_ids,
	},
	.probe = gc2607_probe,
	.remove = gc2607_remove,
	.id_table = gc2607_id,
};

module_i2c_driver(gc2607_i2c_driver);

MODULE_SOFTDEP("pre: v4l2-fwnode v4l2-cci");
MODULE_DESCRIPTION("GalaxyCore GC2607 sensor driver");
MODULE_AUTHOR("Alex Daichendt <alex@daichendt.one>");
MODULE_LICENSE("GPL");
