# GC2607 Camera - Quick Start After Reboot

## After Reboot

1. **Initialize the camera** (loads modules and configures everything):
   ```bash
   sudo ./init_camera.sh
   ```

2. **Capture a test image**:
   ```bash
   ./quick_capture.sh
   feh test.png
   ```

## Current Status

- ✅ Driver fully functional with exposure/gain controls
- ✅ Default settings: exposure=1300, gain=220 (optimal brightness)
- ✅ No post-processing needed - images are properly exposed natively

## Manual Capture

```bash
# Capture raw image
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=myimage.raw

# Convert and view
./view_raw_bright.py myimage.raw 1.0
feh test.png
```

## Adjust Exposure/Gain Manually

```bash
# List current values
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls | grep -E "(exposure|gain)"

# Adjust values
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1200
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl analogue_gain=200

# Capture with new settings
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=test.raw
```

## Troubleshooting

If capture fails with "Broken pipe":
```bash
# Reconfigure CSI2 formats
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":0 [fmt:SGRBG10_1X10/1920x1080]'
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":1 [fmt:SGRBG10_1X10/1920x1080]'
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0[1]'
```

## Phase 7 Status

**✅ COMPLETE** - Exposure and gain controls implemented and working!
- Exposure control: range 4-1335, default 1300
- Gain control: range 64-255, default 220
- Images are properly exposed out of the box
