# How Everything Fits Together

A bird's-eye map of this project for someone who just stumbled onto the repo and
wants to understand how the pieces connect — from the physical camera sensor up to
a GStreamer app showing video.

There are four "worlds" in this repo, all tied together by `scripts/`:

- **Patches** — surgical edits to upstream code we don't own (the `third_party/`
  submodules), kept separate so the submodules stay clean and updatable.
- **DKMS** — the mechanism that compiles our kernel modules and **re-compiles them
  automatically on every kernel upgrade**, so the camera survives a system update.
- **HAL assets** — binary tuning data (`.aiqb` 3A/color model + graph XMLs) that
  can't live as source patches; copied into the HAL checkout before it builds.
- **Kernel state** — what actually ends up live on the machine: the `.ko` modules
  in `/lib/modules/.../updates/dkms`, plus `/etc` config that auto-loads them and
  fixes `/dev/ipu-psys0` permissions.

## The big picture

```text
+------------------------------------------------------------------------------+
| (1) SOURCE OF TRUTH  (this repo, version-controlled)                          |
+------------------------------------------------------------------------------+
|                                                                              |
|   gc2607-kernel/          ipu-bridge-gc2607/        third_party/             |
|   |- gc2607.c             |- ipu-bridge.c           |- ipu6-drivers/    (sub)|
|   |- Makefile             |- dkms.conf              |- ipu6-camera-hal/ (sub)|
|   |- dkms.conf                                                               |
|                                                                              |
|   patches/                assets/hal/               config/                 |
|   |- hal/0001 profile+pad |- *.aiqb  (3A tuning)    |- modules-load.d/       |
|   |- hal/0002 sensor xml  |- graph_settings.xml     |- udev/rules.d/         |
|   |- hal/0003 werror      |- graph_descriptor.xml                            |
|   |- ipu6-drivers/0001 cio2-bridge (legacy fallback)                         |
|                                                                              |
|   scripts/  <- the GLUE that drives everything below                         |
+------------------------------------------------------------------------------+
            |
            |  scripts orchestrate 4 transformations
            |
   +--------+----------------+----------------------+--------------------+
   |                         |                      |                    |
   v PATCH                   v BUILD/INSTALL (DKMS)  v COPY ASSETS        v SYSTEM CONFIG
 apply-patches.sh        install-*-dkms.sh (x3)   install-hal-         install-system-
 patches/* -> submodules gc2607 / psys /          assets.sh            config.sh
                         ipu-bridge               assets/* -> HAL      /etc modules+udev
            |                      |                      |                    |
            v                      v                      v                    v
+------------------------------------------------------------------------------+
| (2) INSTALLED KERNEL STATE  (/usr/src, /lib/modules/.../updates/dkms, /etc)   |
+------------------------------------------------------------------------------+
|                                                                              |
|   gc2607.ko          intel-ipu6-psys.ko        ipu-bridge.ko                 |
|   (DKMS)             (DKMS)                    (DKMS override)                |
|   autoloaded via     autoloaded via            depmod priority               |
|   ACPI modalias      aux-bus modalias          beats distro copy             |
|   GCTI2607                                                                   |
|                                                                              |
|   /etc/udev/rules.d/70-ipu6-psys.rules  (chmod /dev/ipu-psys0 -> video)      |
+------------------------------------------------------------------------------+
```

## Runtime data flow

Once everything is installed, this is the path a frame takes:

```text
  HARDWARE             KERNEL                                USERSPACE (HAL)
  --------             ------                                ---------------
 +---------+    i2c    +----------+   builds    +--------+
 | GC2607  |--GCTI2607-| gc2607.ko|   graph     |ipu-    |
 | sensor  |           | V4L2     |<----------->|bridge  |
 | SGRBG10 |           | subdev   |             |.ko     |
 |1920x1080|           +----+-----+             +--------+
 +----+----+                | exposure / gain / vblank  (3A writes back ^)
      | MIPI CSI-2          v
      | 336 MHz       +----------+        +----------+
      +-------------->| IPU6 ISYS|------->| IPU6 PSYS|
                      | raw cap  | RAW10  | /dev/    |
                      |/dev/video|        | ipu-psys0|
                      +----------+        +----+-----+
                                               | loads: *.aiqb (tuning)
                                               |        graph_*.xml
                                               v
                                      +------------------+
                                      | libcamhal (HAL)  |  3A loop:
                                      | + gc2607-uf.xml  |  AE/AWB -> V4L2
                                      | + 3 patches      |  (back to sensor)
                                      | pad 1080 -> 1088 |
                                      +--------+---------+
                                               | NV12 1920x1080 @ 30fps
                                               v
                                      +------------------+
                                      | icamerasrc       |  (GStreamer)
                                      +--------+---------+
                          +--------------------+------------------+
                          v                    v                  v
                   verify-hal.sh      capture-gst-frame   virtual-camera.sh
                   (preview)          (JPEG stills)       (v4l2loopback -> apps)
```

## The three kernel modules, one line each

| Module | What it drives |
|--------|----------------|
| `gc2607.ko` | the **sensor** chip — speaks GC2607's i2c register language |
| `ipu-bridge.ko` | the **matchmaker** — builds the sensor &harr; IPU6 media graph link that x86 ACPI doesn't describe |
| `intel-ipu6-*.ko` | the **IPU6** hardware — ISYS raw capture + PSYS image processing |

### Why the bridge is needed

On phones/ARM boards, a Device Tree spells out the wiring between the sensor and the
image processor (which port connects to which, at what link frequency). On x86 ACPI
laptops that wiring is **missing** — ACPI says the sensor *exists* (the `GCTI2607`
ID that auto-loads `gc2607.ko`) but not how it connects to IPU6. The `ipu-bridge`
synthesizes that missing connection at boot, so ISYS and the sensor can find each
other. The stock bridge that ships with modern kernels doesn't list `GCTI2607`, so
this repo installs a patched copy via DKMS that overrides it.

## Where to dig deeper

- `gc2607-kernel/FINDINGS.md` — the 30 fps fix (PLL / blanking) and the gain model
- `docs/ipu-bridge.md` — the bridge override in detail
- `docs/assets.md` — the HAL tuning assets and their checksums
- `docs/troubleshooting.md` — when the stack doesn't come up
- `docs/virtual-camera.md` — exposing the camera to Discord/Telegram via v4l2loopback
