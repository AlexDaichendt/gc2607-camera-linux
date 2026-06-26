# Post-Reboot Quick Start

## First Time Setup (One Time Only)

```bash
cd /home/abbood/dev/camera-driver-dev/gc2607-v4l2-driver
sudo ./setup_permissions.sh
```

**Then log out and log back in** (or reboot)

## After Every Reboot

```bash
cd /home/abbood/dev/camera-driver-dev/gc2607-v4l2-driver
./claude.init
```

This will:
- Load all required kernel modules
- Initialize the GC2607 camera driver
- Configure formats and exposure/gain
- Show you next steps

## Using with OBS Studio / Google Meet

After running `./claude.init`, create a virtual RGB camera:

```bash
./create_virtual_camera.sh
```

This creates `/dev/video10` with RGB output. Use this device in OBS/Meet.

## Adjust Brightness Live

While camera is running:

```bash
# Brighter
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1335,analogue_gain=255

# Darker
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1200,analogue_gain=220
```

## Current Status

**Phase 7 Complete ✅**
- Exposure and gain controls working
- White balance fixed (green tint corrected)
- Optimal defaults: exposure=1335, gain=253
- Ready for real-time use with applications
