# AUR packaging

Arch Linux packages for the full GC2607 camera stack, an alternative to running
the `scripts/install-*.sh` steps by hand. Each package mirrors one stage of the
manual bring-up:

| Package | What it ships | Build |
|---------|---------------|-------|
| [`gc2607-dkms`](gc2607-dkms/) | GC2607 V4L2 sensor module (binds GCTI2607) | DKMS |
| [`gc2607-ipu-bridge-dkms`](gc2607-ipu-bridge-dkms/) | patched `ipu-bridge.ko` (adds the GC2607 sensor-table entry + mount quirk) | DKMS |
| [`gc2607-ipu6-camera-hal`](gc2607-ipu6-camera-hal/) | IPU6 HAL (libcamhal) patched for GC2607 + tuning assets | cmake → `/usr` |
| [`gc2607-virtual-camera`](gc2607-virtual-camera/) | v4l2-relayd virtual webcam + system camera config | files only |

The IPU6 PSYS module (`/dev/ipu-psys0`) is not packaged here: it is pulled in
transitively as `intel-ipu6-dkms-git`, a dependency of the `intel-ipu6-camera-bin`
the HAL links against. Its upstream PSYS build is identical to what a local DKMS
package would produce, so shipping our own would just be a redundant copy.

The two DKMS packages rebuild automatically on every kernel upgrade (via the
`dkms` pacman hook), which is the whole reason for packaging: an out-of-tree
module installed by hand is silently lost on the next kernel bump.

> These are **not on the AUR yet** — build them from a checkout of this repo.
> They are VCS (`-git`) packages: they build from the latest `main` (the Intel
> HAL submodule is pinned to a validated commit inside the PKGBUILD), and
> `pkgver()` derives a version like `0.3.1.r42.gdeadbee` from the commit count
> and hash.

## Prerequisites

A few dependencies live on the AUR and must be installed first (raw `makepkg`
does not fetch AUR deps; an AUR helper such as `paru`/`yay` does):

```bash
paru -S intel-ipu6-camera-bin icamerasrc-git
```

`intel-ipu6-camera-bin` transitively pulls `intel-ipu6-dkms-git` (the PSYS
module). `v4l2-relayd` and `v4l2loopback-dkms` are pulled from the official
repos as normal dependencies.

## Install

Build in dependency order — the kernel modules and the HAL first, then the
virtual-camera package that ties them together:

```bash
git clone https://github.com/AlexDaichendt/gc2607-camera-linux.git
cd gc2607-camera-linux/packaging/aur

(cd gc2607-dkms              && makepkg -si)
(cd gc2607-ipu-bridge-dkms   && makepkg -si)
(cd gc2607-ipu6-camera-hal   && makepkg -si)
(cd gc2607-virtual-camera    && makepkg -si)

# Reboot for a clean first bring-up (the DKMS packages replace in-use kernel
# modules), then pick "GC2607 Virtual Camera" in your app.
reboot
```

With an AUR helper and these published, the last package alone would pull the
whole chain (`paru -S gc2607-virtual-camera`).

### What the scriptlets do

`gc2607-virtual-camera`'s `.install` enables `v4l2-relayd.service` and brings up
the v4l2loopback device, so the camera works after install + reboot with no
further steps. The DKMS packages `modprobe` their modules on install where
possible; modules that are already live take effect on the next reboot.

Auto-enabling a service deviates from Arch packaging guidelines — drop the
`systemctl enable --now` line from `gc2607-virtual-camera.install` if publishing
to the AUR.

`makepkg -si` installs via `pacman`, so removal is the reverse:

```bash
pacman -R gc2607-virtual-camera gc2607-ipu6-camera-hal \
          gc2607-ipu-bridge-dkms gc2607-dkms
```

## Publishing to the AUR

Each package is its own AUR git repo. `.SRCINFO` is committed alongside the
`PKGBUILD` and must be regenerated after any PKGBUILD change:

```bash
makepkg --printsrcinfo > .SRCINFO
```

Once tagged releases exist, consider switching the `source=` entries to release
tarballs and dropping the `-git` suffix for reproducible, pinned packages.
