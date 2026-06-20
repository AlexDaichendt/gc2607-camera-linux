# Troubleshooting

## Discord Shows `ipu6` But The Image Is Black

The `ipu6` devices are raw IPU6/ISYS nodes, not a normal processed webcam. Discord cannot use raw
Bayer frames directly.

Use the virtual camera:

```sh
systemctl --user start gc2607-discord-camera.service
```

Then select:

```text
GC2607 HAL Camera
```

## Virtual Camera Is Missing

Check the loopback module:

```sh
ls -l /dev/video60
modinfo v4l2loopback
```

Load it manually:

```sh
sudo modprobe v4l2loopback video_nr=60 card_label="GC2607 HAL Camera" exclusive_caps=1
```

## Camera Is Busy

Stop PipeWire/WirePlumber while testing:

```sh
systemctl --user stop wireplumber.service 2>/dev/null || true
```

Find users of video/media nodes:

```sh
sudo fuser -v /dev/video* /dev/v4l-subdev* /dev/media*
```

## Need To Reload The GC2607 Driver

```sh
cd "$DRIVER"
echo i2c-GCTI2607:00 | sudo tee /sys/bus/i2c/drivers/gc2607/unbind
sudo rmmod gc2607
sudo insmod ./gc2607.ko
```

If bind reports `Device or resource busy`, the sensor may already be bound.

## HAL Fails Before Stream-On

Check that `/dev/ipu-psys0` exists:

```sh
ls -l /dev/ipu-psys0
```

If it is missing, build/load the IPU6 PSYS driver from Intel's `ipu6-drivers` repo.

## Image Is Upside Down In Discord

The Discord bridge rotates by default:

```sh
FLIP_METHOD=rotate-180 ~/bin/gc2607-discord-camera.sh
```

To test other orientations:

```sh
FLIP_METHOD=none ~/bin/gc2607-discord-camera.sh
FLIP_METHOD=vertical-flip ~/bin/gc2607-discord-camera.sh
```

## The GStreamer Bridge Uses Battery

The virtual camera bridge keeps the sensor, IPU6 pipeline, and GStreamer conversion path active.
Start it for calls and stop it afterward:

```sh
systemctl --user start gc2607-discord-camera.service
systemctl --user stop gc2607-discord-camera.service
```
