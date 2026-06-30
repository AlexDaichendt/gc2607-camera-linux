# On-Demand Virtual Camera

The practical compatibility path is:

```text
icamerasrc -> v4l2-relayd -> v4l2loopback -> Discord/Telegram/browser
```

[`v4l2-relayd`](https://gitlab.com/vicamo/v4l2-relayd) is the canonical userspace bridge for the
IPU6 HAL problem. It owns the `v4l2loopback` device as a producer and powers the real GC2607 source
**only while a consumer has the loopback open**, using v4l2loopback's `V4L2_EVENT_PRI_CLIENT_USAGE`
event. The real GC2607/IPU6/HAL pipeline therefore runs only while something actually opens the
virtual camera — messaging apps can stay open all day with the sensor idle.

## Prerequisites

Install `v4l2-relayd` (AUR on Arch/CachyOS):

```sh
paru -S v4l2-relayd
```

## Workflow

Install the desktop integration once:

```sh
"$BRINGUP/scripts/install-virtual-camera-desktop.sh"
```

Create the virtual webcam without powering the real camera:

```sh
"$BRINGUP/scripts/virtual-camera.sh" prepare
```

Start the relayd engine:

```sh
"$BRINGUP/scripts/virtual-camera.sh" start
```

Select this camera in the application:

```text
GC2607 Virtual Camera
```

Stop the engine when done:

```sh
"$BRINGUP/scripts/virtual-camera.sh" stop
```

The `prepare` step loads `v4l2loopback` and registers PipeWire visibility; it does not start relayd.
The `start` step launches relayd as a `systemd --user` service. While no app has the virtual camera
open, relayd feeds the splash image (a cheap black `videotestsrc`) so the node stays discoverable
under `exclusive_caps=1`. The instant an app opens `GC2607 Virtual Camera`, relayd starts the real
`icamerasrc` pipeline; when the last consumer closes, it returns to the splash and powers the sensor
back down. There is no idle-timeout knob any more — start/stop is driven directly by the kernel
open/close events.

## HAL prefix and the two service models

Two ways to run relayd, depending on where the IPU6 HAL is installed:

- **Development (this repo's default):** the HAL lives in `$HOME/opt/gc2607-ipu6`, so relayd runs as
  a `systemd --user` service. `scripts/run-virtual-camera-feeder.sh` points GStreamer at that prefix
  (`LD_LIBRARY_PATH` / `GST_PLUGIN_PATH` / `GST_REGISTRY`) and builds relayd's `-i`/`-o`/`-s`
  pipelines from the `GC2607_*` environment. This is what `virtual-camera.sh start` uses.

- **Packaged (canonical):** install the HAL to `/usr` (a real package, `DESTDIR`-staged), where
  ld.so, pkg-config, and GStreamer auto-discover it with no environment glue. Then drop the relayd
  config at `/etc/v4l2-relayd.d/gc2607.conf` (template: [`config/v4l2-relayd.conf`](../config/v4l2-relayd.conf))
  and enable the packaged system service:

  ```sh
  sudo install -m0644 config/v4l2-relayd.conf /etc/v4l2-relayd.d/gc2607.conf
  sudo systemctl daemon-reload
  sudo systemctl enable --now v4l2-relayd.service
  ```

  The packaged service is hardened (`InaccessibleDirectories=/home`), which is why it requires the
  HAL in `/usr` rather than `$HOME`. On Arch, `/usr` is the only prefix where all of ld.so,
  pkg-config, and GStreamer resolve without extra search-path configuration, so it is also the right
  target for eventual packaging.

## Persistence Across Reboots

The manual workflow above does not survive a reboot: `v4l2loopback` is not loaded, `/dev/video60`
does not exist, and relayd is not running until you run `start` again.

To wire it up once and have it come back automatically on every boot:

```sh
"$BRINGUP/scripts/install-virtual-camera-service.sh"
```

This is re-runnable and installs three idempotent pieces:

1. `/etc/modules-load.d` + `/etc/modprobe.d` drop-ins so `v4l2loopback` auto-loads at boot with the
   GC2607 options, making `/dev/video60` exist before you log in (asks for `sudo`).
2. A `systemd --user` service (`gc2607-camera.service`) that runs `virtual-camera.sh run` on login,
   ordered after `pipewire`/`wireplumber`.
3. The WirePlumber desktop integration (via `install-virtual-camera-desktop.sh`).

This persists the *virtual device and the relayd engine* — not the real camera. relayd keeps
`/dev/video60` discoverable via the splash, and the real GC2607/IPU6 pipeline still only spins up
while an app is actually using the virtual camera. The service is `--user` (no
`loginctl enable-linger`) because PipeWire registration needs the graphical session's media stack.
(Once the HAL is packaged to `/usr`, you can switch to the system `v4l2-relayd.service` instead,
which runs before login.)

Undo it by disabling the service and removing the drop-ins:

```sh
systemctl --user disable --now gc2607-camera.service
sudo rm -f /etc/modules-load.d/gc2607-v4l2loopback.conf /etc/modprobe.d/gc2607-v4l2loopback.conf
```

## Status And Logs

```sh
"$BRINGUP/scripts/virtual-camera.sh" status
"$BRINGUP/scripts/virtual-camera.sh" logs
```

Remove the virtual device when no application is using it:

```sh
"$BRINGUP/scripts/virtual-camera.sh" unload
```

## Defaults

The default virtual node is `/dev/video60`, with `exclusive_caps=1` for WebRTC compatibility.
Change the node before `prepare` or `start` if needed:

```sh
GC2607_VCAM_VIDEO_NR=70 "$BRINGUP/scripts/virtual-camera.sh" start
```

The default output is 1280x720 YUY2 at 30 fps. Override it if an application needs a different mode:

```sh
GC2607_VCAM_WIDTH=1920 \
GC2607_VCAM_HEIGHT=1080 \
"$BRINGUP/scripts/virtual-camera.sh" start
```

Limit an accidentally forgotten session with systemd's runtime limit syntax:

```sh
GC2607_VCAM_MAX_RUNTIME=90min "$BRINGUP/scripts/virtual-camera.sh" start
```

Run relayd in the foreground with debug logging:

```sh
GC2607_RELAYD_DEBUG=1 "$BRINGUP/scripts/virtual-camera.sh" run
```

## Notes

- `start` may ask for `sudo` the first time because loading `v4l2loopback` is a kernel-module
  operation.
- Some applications only rescan cameras when opening their camera picker or joining a call. If the
  virtual camera is not visible, run `start`, then reopen the camera picker.
- The desktop integration hides WirePlumber's raw IPU6 and uncalibrated libcamera GC2607 sources.
  Those sources can otherwise keep `/dev/video0` busy and prevent relayd from opening the sensor.
- If `start` reports `/dev/video0` is still busy, close any camera preview or call that previously
  selected the built-in GC2607 camera. Telegram may keep the old camera handle until its camera
  settings/call window is closed, or until Telegram is quit and reopened.
- With `exclusive_caps=1`, the loopback device must have a producer attached before many apps will
  list it. relayd's splash stream satisfies that discovery requirement without powering the sensor.
- If `v4l2loopback` is already loaded without the GC2607 virtual device, unload it when idle and
  rerun `prepare` or `start`.
