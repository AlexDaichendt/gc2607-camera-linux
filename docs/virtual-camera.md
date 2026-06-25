# On-Demand Virtual Camera

The practical compatibility path is:

```text
icamerasrc -> GStreamer conversion -> v4l2loopback -> Discord/Telegram/browser
```

This is intentionally not installed as a boot service. Messaging apps can stay open all day, but
the real GC2607/IPU6/HAL pipeline only runs while something actually opens the virtual camera.

## Workflow

Install the desktop integration once:

```sh
"$BRINGUP/scripts/install-virtual-camera-desktop.sh"
```

Create the virtual webcam without starting the real camera:

```sh
"$BRINGUP/scripts/virtual-camera.sh" prepare
```

Arm the on-demand watcher:

```sh
"$BRINGUP/scripts/virtual-camera.sh" start
```

Select this camera in the application:

```text
GC2607 Virtual Camera
```

Stop the watcher and all virtual-camera helper streams when done:

```sh
"$BRINGUP/scripts/virtual-camera.sh" stop
```

The `prepare` step loads `v4l2loopback` and starts a synthetic black standby stream. That standby
stream is what keeps `/dev/video60` visible as a capture device for browser/WebRTC camera pickers
while `exclusive_caps=1` is enabled. It does not open the real GC2607 camera.

The `start` step runs a lightweight watcher. When an app opens `GC2607 Virtual Camera`, the watcher
stops the standby stream and starts the real `icamerasrc` feeder. After the app closes the virtual
camera, the watcher waits `GC2607_VCAM_IDLE_SECONDS` seconds and stops the real feeder again.

The idle standby stream is cheap but not free: it keeps a small GStreamer `videotestsrc` pipeline
running so apps can discover the camera. Run `stop` when you want zero virtual-camera helper CPU.

## Persistence Across Reboots

The manual workflow above does not survive a reboot: `v4l2loopback` is not loaded, `/dev/video60`
does not exist, and the watcher is not armed until you run `start` again. If you reboot and join a
call before remembering to do that, the camera is simply missing.

To wire it up once and have it come back automatically on every boot:

```sh
"$BRINGUP/scripts/install-virtual-camera-service.sh"
```

This is re-runnable and installs three idempotent pieces:

1. `/etc/modules-load.d` + `/etc/modprobe.d` drop-ins so `v4l2loopback` auto-loads at boot with the
   GC2607 options, making `/dev/video60` exist before you log in (asks for `sudo`).
2. A `systemd --user` service (`gc2607-camera.service`) that runs `virtual-camera.sh
   watch-foreground` on login, ordered after `pipewire`/`wireplumber`.
3. The WirePlumber desktop integration (via `install-virtual-camera-desktop.sh`).

This persists the *virtual device and the on-demand watcher* — not the real camera. The standby
stream keeps `/dev/video60` discoverable, and the real GC2607/IPU6 pipeline still only spins up
while an app is actually using the virtual camera, exactly as with the manual `start` flow. The
service is `--user` (no `loginctl enable-linger`) because the watcher needs the graphical session's
PipeWire stack, which only exists once you are logged in.

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

The default feeder output is 1280x720 YUY2 at 30 fps. Override it if an application needs a
different mode:

```sh
GC2607_VCAM_WIDTH=1920 \
GC2607_VCAM_HEIGHT=1080 \
"$BRINGUP/scripts/virtual-camera.sh" start
```

Limit an accidentally forgotten session with systemd's runtime limit syntax:

```sh
GC2607_VCAM_MAX_RUNTIME=90min "$BRINGUP/scripts/virtual-camera.sh" start
```

Change the idle timeout before the real camera is stopped after the last consumer closes:

```sh
GC2607_VCAM_IDLE_SECONDS=15 "$BRINGUP/scripts/virtual-camera.sh" start
```

For debugging only, start the real feeder immediately:

```sh
"$BRINGUP/scripts/virtual-camera.sh" force-start
```

## Notes

- `start` may ask for `sudo` the first time because loading `v4l2loopback` is a kernel-module
  operation.
- Some applications only rescan cameras when opening their camera picker or joining a call. If the
  virtual camera is not visible, run `start`, then reopen the camera picker.
- The desktop integration hides WirePlumber's raw IPU6 and uncalibrated libcamera GC2607 sources.
  Those sources can otherwise keep `/dev/video0` busy and prevent the Intel HAL feeder from
  starting.
- If `start` reports `/dev/video0` is still busy, close any camera preview or call that previously
  selected the built-in GC2607 camera. Telegram may keep the old camera handle until its camera
  settings/call window is closed, or until Telegram is quit and reopened.
- With `exclusive_caps=1`, the loopback device must have a producer attached before many apps will
  list it. The standby stream exists only to satisfy that discovery requirement without powering the
  real camera.
- If `v4l2loopback` is already loaded without the GC2607 virtual device, unload it when idle and
  rerun `prepare` or `start`.
