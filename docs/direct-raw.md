# Direct Raw Capture

The final application path uses Intel IPU6 HAL/PSYS, but direct raw capture is useful to verify that
the kernel sensor driver and media graph are working.

The expected raw mode is:

```text
format: BA10 / SGRBG10_1X10
size: 1920x1080
bytesperline: 3840
```

Configure a typical IPU6 media graph:

```sh
media-ctl -d /dev/media0 -l '"gc2607 5-0037":0 -> "Intel IPU6 CSI2 0":0 [1]' 2>&1 || true
media-ctl -d /dev/media0 -l '"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0 [1]' 2>&1 || true

media-ctl -d /dev/media0 -V '"gc2607 5-0037":0 [fmt:SGRBG10_1X10/1920x1080]' 2>&1 || true
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":0 [fmt:SGRBG10_1X10/1920x1080]'
media-ctl -d /dev/media0 -V '"Intel IPU6 CSI2 0":1 [fmt:SGRBG10_1X10/1920x1080]'

v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=BA10
```

Capture a short raw frame:

```sh
timeout 8s v4l2-ctl -d /dev/video0 \
  --stream-mmap=4 \
  --stream-count=2 \
  --stream-to=/tmp/gc2607_raw.bin
```

Direct raw output will not look like a normal webcam without demosaic, color correction, exposure,
white balance, and tone mapping. Use this only as a low-level sanity check; use the HAL path for real
camera output.

Useful controls exposed by the patched driver:

```sh
v4l2-ctl -d /dev/v4l-subdev6 --list-ctrls
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl exposure=1200
v4l2-ctl -d /dev/v4l-subdev6 --set-ctrl analogue_gain=200
```

Subdevice numbers vary. If `/dev/v4l-subdev6` is not GC2607, find it with:

```sh
media-ctl -d /dev/media0 --print-topology | rg -n "gc2607|v4l-subdev"
```
