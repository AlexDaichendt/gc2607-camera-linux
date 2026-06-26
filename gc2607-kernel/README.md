# GC2607 Camera Driver for Linux

A fully functional Linux V4L2 driver for the GalaxyCore GC2607 camera sensor, integrated with Intel IPU6 on x86_64 systems.

## Overview

This driver successfully ports the GC2607 sensor from embedded platforms to mainline Linux, enabling camera functionality on laptops with Intel IPU6 that use this sensor.

**Status:** ✅ **FULLY FUNCTIONAL** - Camera working with OBS Studio and video applications!

### Supported Hardware

- **Sensor:** GalaxyCore GC2607
- **Platform:** Intel IPU6 (tested on Huawei MateBook Pro VGHH-XX)
- **Interface:** MIPI CSI-2 (2 lanes, 672 Mbps/lane)
- **Resolution:** 1920x1080 @ 30fps
- **Format:** 10-bit RAW Bayer (GRBG pattern)
- **ACPI HID:** GCTI2607

## Project Status

- ✅ Phase 1: Skeleton driver with ACPI binding
- ✅ Phase 2: Power management and sensor detection
- ✅ Phase 3: Register initialization (122 registers)
- ✅ Phase 4: V4L2 integration (async subdev, pad ops, controls)
- ✅ Phase 5: IPU6 bridge integration
- ✅ Phase 6: Image capture and streaming **SUCCESS!**
- ✅ Phase 7: Exposure & gain controls **COMPLETE!**

## Features

✅ Full V4L2 subdev integration
✅ Intel IPU6 media controller support
✅ MIPI CSI-2 interface (2 lanes @ 336 MHz)
✅ 1920x1080 @ 30fps capture
✅ 10-bit RAW Bayer output
✅ Power management via INT3472 PMIC
✅ Runtime PM support
✅ Proper reset sequencing
✅ **Exposure control (V4L2_CID_EXPOSURE) - range 4-2002**
✅ **Analog gain control (V4L2_CID_ANALOGUE_GAIN) - LUT index 0-16**
✅ **Gray world white balance** during Bayer-to-RGB conversion
✅ **OBS Studio integration with virtual RGB camera**
✅ **Google Meet / Chrome / Chromium support (24fps I420)**

## Prerequisites

### Required Packages (Arch Linux)

```bash
# Core driver dependencies
sudo pacman -S base-devel linux-headers v4l-utils media-ctl python-pillow python-numpy feh

# For OBS Studio integration (optional)
sudo pacman -S v4l2loopback-dkms gstreamer gst-plugins-base gst-plugins-good
```

### Modified IPU6 Bridge Module

**Important:** This driver requires a modified `ipu_bridge` kernel module that recognizes the GC2607 sensor.

#### Installation

```bash
# 1. Run the setup script to download kernel source
./setup_ipu_bridge_mod.sh

# 2. Compile the modified bridge module
./compile_ipu_bridge_simple.sh

# The script will automatically:
# - Add GCTI2607 support to ipu-bridge.c
# - Compile against your running kernel
# - Install the modified module
# - Create a backup of the original
```

## Building the Driver

```bash
make
```

## Usage

### Quick Start - Capture Your First Image

```bash
# 1. Load required kernel modules
sudo modprobe videodev
sudo modprobe v4l2-async
sudo modprobe ipu_bridge
sudo modprobe intel-ipu6
sudo modprobe intel-ipu6-isys

# 2. Load the GC2607 driver
sudo insmod gc2607.ko

# 3. Verify the sensor is detected
media-ctl -d /dev/media0 --print-topology | grep gc2607
# You should see: - entity 349: gc2607 5-0037 (...)

# 4. Configure the video device format
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10

# 5. Enable the media pipeline link
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'

# 6. Capture an image
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=capture.raw

# 7. Convert RAW to viewable PNG (with brightness boost)
./view_raw_bright.py capture.raw 5.0

# 8. View the image
feh capture.png
```

### Automated Capture Script

For convenience, you can create a script:

```bash
#!/bin/bash
# capture.sh - Quick capture script

# Configure and capture
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=capture_$(date +%s).raw

# Convert last captured image
LATEST=$(ls -t capture_*.raw | head -1)
./view_raw_bright.py "$LATEST" 5.0
feh "${LATEST%.raw}.png"
```

### Using with OBS Studio and Video Applications

The camera outputs raw Bayer format which most applications can't handle directly. Use the virtual RGB camera:

```bash
# 1. Initialize the camera (only needed once per boot)
sudo ./init_camera.sh

# 2. Create virtual RGB camera (leave running in background)
./create_virtual_camera.sh
```

Now in OBS Studio:
1. Add Source → Video Capture Device (V4L2)
2. Select device: **"GC2607 RGB"** from the dropdown
3. The camera will appear with proper RGB colors and correct orientation

**Note:** The `create_virtual_camera.sh` script must keep running while using the camera.

### Using with Google Meet and Chrome/Chromium

**Important:** Chrome/Chromium's PipeWire camera support blocks v4l2loopback virtual cameras. You need to disable it:

#### One-time Setup for Chrome/Chromium:

1. Open Chrome/Chromium and navigate to: `chrome://flags`
2. Search for: **"pipewire"**
3. Find: **"PipeWire Camera support"**
4. Set to: **Disabled**
5. Click **"Relaunch"**

#### Using the Camera:

```bash
# Option 1: Use create_virtual_camera.sh (works for both OBS and Meet)
./create_virtual_camera.sh

# Option 2: Use reload_for_chrome.sh (optimized for Chrome with I420 format)
./reload_for_chrome.sh
```

Then in Google Meet:
1. Join a meeting
2. Click Settings (gear icon) → Video
3. Select: **"GC2607 RGB Camera"** from the dropdown

**Note:** Your external USB cameras (like Logitech) will still work perfectly with PipeWire disabled. Both cameras will appear in the list.

### Adjusting Exposure and Gain

The camera uses a gain LUT (lookup table) with 17 entries (0-16), not raw gain values.

```bash
# List available controls
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls

# Adjust exposure (range: 4-2002)
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=2002

# Adjust gain (range: 0-16, LUT index)
# 0 = 1.0x gain (lowest noise)
# 4 = 2.0x gain
# 8 = 4.0x gain
# 16 = 15.8x gain (max)
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl analogue_gain=16

# Optimal defaults for indoor lighting (set automatically by scripts)
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=2002,analogue_gain=16
```

### White Balance

All camera scripts automatically apply **gray world white balance** during Bayer-to-RGB conversion using GStreamer's `frei0r-filter-coloradj-rgb`:

- **Red gain:** 1.034
- **Green gain:** 1.000 (reference)
- **Blue gain:** 1.246

These values are calibrated for natural color reproduction. To recalibrate for your lighting conditions:

```bash
# Capture a test frame
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=wb_test.raw

# Calculate optimal white balance gains
./calculate_wb_gains.py wb_test.raw

# Use the calculated gains with the WB script
./create_virtual_camera_wb.sh <R_GAIN> <G_GAIN> <B_GAIN>
```

## Troubleshooting

### Image is too dark or too bright
Adjust the exposure and gain controls:
```bash
# Increase brightness (max values)
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=2002,analogue_gain=16

# Decrease brightness (for bright conditions)
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1000,analogue_gain=8

# For raw captures, use white balance script:
./view_raw_wb.py capture.raw 5.0

# Or use brightness multiplier without white balance:
./view_raw_bright.py capture.raw 8.0  # Try values between 3.0 and 10.0
```

### Image is all black
Check if your laptop has a physical camera privacy slider/cover. Many laptops include a hardware privacy mechanism.

### "Link has been severed" error
The media link isn't enabled. Run:
```bash
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'
```

### "Format mismatch" error
Ensure you're using the BA10 pixel format (GRBG Bayer):
```bash
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
```

### Sensor not detected
1. Check that ipu_bridge recognizes GCTI2607:
   ```bash
   sudo dmesg | grep -i "GCTI2607\|gc2607"
   ```
2. Verify the modified ipu_bridge is loaded:
   ```bash
   modinfo ipu_bridge
   strings /lib/modules/$(uname -r)/kernel/drivers/media/pci/intel/ipu-bridge.ko.zst | grep GCTI2607
   ```

### Camera not appearing in Google Meet/Chrome

**Cause:** Chrome's PipeWire camera support blocks v4l2loopback virtual cameras.

**Solution:**
1. Go to `chrome://flags` in Chrome/Chromium
2. Search for "pipewire"
3. Disable "PipeWire Camera support"
4. Restart the browser
5. Run `./reload_for_chrome.sh` to restart the camera pipeline
6. Refresh Google Meet

The camera should now appear as "GC2607 RGB Camera" in the device list.

## Architecture

### Media Pipeline

```
┌─────────────┐      ┌──────────────────┐      ┌─────────────────────┐
│  gc2607     │      │ Intel IPU6 CSI2 0│      │ Intel IPU6 ISYS     │
│  5-0037     │─────▶│  (MIPI Receiver) │─────▶│ Capture 0           │
│ (Sensor)    │      │  /dev/v4l-subdev0│      │ /dev/video0         │
└─────────────┘      └──────────────────┘      └─────────────────────┘
 /dev/v4l-subdev6
   SGRBG10_1X10           SGRBG10_1X10              BA10 (GRBG)
   1920x1080              1920x1080                 1920x1080
```

### Key Components

- **gc2607.c** - Main driver (V4L2 subdev, power management, register initialization)
- **ipu-bridge.c** - Modified to recognize GCTI2607 sensor
- **view_raw_bright.py** - RAW Bayer to PNG converter with brightness boost
- **view_raw_wb.py** - RAW Bayer to PNG converter with gray world white balance
- **calculate_wb_gains.py** - Calculate optimal white balance gains from raw capture
- **create_virtual_camera.sh** - Create virtual RGB camera with white balance (OBS/YUY2)
- **create_virtual_camera_wb.sh** - Parameterized white balance version
- **reload_for_chrome.sh** - Create virtual RGB camera for Chrome/Meet (I420, 24fps)
- **compile_ipu_bridge_simple.sh** - Builds modified ipu_bridge module

## Technical Details

### Sensor Specifications
- **Resolution:** 1920x1080
- **Frame Rate:** 30 fps
- **Bit Depth:** 10-bit RAW
- **Bayer Pattern:** GRBG (MEDIA_BUS_FMT_SGRBG10_1X10)
- **I2C Address:** 0x37
- **Chip ID:** 0x2607

### MIPI Configuration
- **Lanes:** 2
- **Link Frequency:** 336 MHz
- **Data Rate:** 672 Mbps/lane
- **Pixel Rate:** 134.4 MHz

### Power Management
- **PMIC:** INT3472:01 (intel_skl_int3472_discrete)
- **Clock:** 19.2 MHz from platform
- **Regulators:** avdd (INT3472:01), dovdd (dummy), dvdd (dummy)
- **Reset GPIO:** Provided by INT3472 PMIC
- **Reset Sequence:** HIGH (20ms) → LOW (20ms) → HIGH (10ms)

## Test Scripts

- `test_phase4.sh` - Verify V4L2 integration
- `test_camera_streaming.sh` - Check IPU6 integration
- `investigate_ipu_bridge.sh` - Analyze bridge sensor support
- `QUICK_TEST.sh` - Quick functionality test
- `view_raw.py` - Basic RAW converter
- `view_raw_bright.py` - RAW converter with brightness boost

## Future Enhancements

The driver is fully functional and ready for production use. Potential improvements include:

**High Priority:**
- Auto-exposure (AE) algorithm
- Auto white balance (AWB)
- Improved demosaicing algorithm

**Medium Priority:**
- Multiple resolution support (720p, 480p, etc.)
- Frame rate control (15fps, 24fps options)
- Test pattern mode for debugging

**Low Priority:**
- Auto-focus support (if VCM present)
- HDR support
- Advanced ISP features

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Complete development guide and technical details
- **[INT3472_INTEGRATION_ANALYSIS.md](INT3472_INTEGRATION_ANALYSIS.md)** - PMIC integration analysis

## References

- [V4L2 Documentation](https://www.kernel.org/doc/html/latest/userspace-api/media/v4l/v4l2.html)
- [Media Controller Documentation](https://www.kernel.org/doc/html/latest/userspace-api/media/mediactl/media-controller.html)
- [Intel IPU6 Driver](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/media/pci/intel)

## License

This driver is released under the GPL-2.0 license, consistent with the Linux kernel.

## Contributing

Contributions welcome! Areas of interest:
- Auto-exposure/auto-gain algorithms
- Multi-resolution support
- Other GalaxyCore sensors (GC1029, etc.)
- Testing on different hardware platforms
- OBS Studio plugin for native Bayer support
- Special thanks to [yegor-alexeyev](https://github.com/yegor-alexeyev) for suggesting that the Matebook Pro 2024 VGHH-XX has the GC2607 sensor in [this post](https://github.com/intel/ipu6-drivers/issues/399#issuecomment-3707318638)

## Acknowledgments

- Reference driver from Ingenic T41 platform
- Linux kernel V4L2 subsystem documentation
- Intel IPU6 driver developers

---

**Status:** ✅ Production ready - Full exposure/gain control, OBS Studio & Google Meet compatible
**Tested on:** Huawei MateBook Pro VGHH-XX
**Kernel:** 6.17.9-arch1-1
**Last Updated:** January 7, 2026
**Achievement:** Successfully ported proprietary embedded camera driver to mainline Linux V4L2 with IPU6 integration, full manual controls, real-time video streaming, and WebRTC compatibility
