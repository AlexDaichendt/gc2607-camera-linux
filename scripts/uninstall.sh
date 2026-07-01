#!/usr/bin/env bash
#
# uninstall.sh — remove the GC2607 camera setup installed by the manual
# scripts/install-*.sh path, so the system is clean for the AUR packages in
# packaging/aur/ (or just to fully back the change out).
#
# Run as root:
#   sudo ./scripts/uninstall.sh          # asks for confirmation
#   sudo ./scripts/uninstall.sh -y       # no prompt
#   sudo KEEP_HAL=1 ./scripts/uninstall.sh   # keep the $HOME HAL build
#
# Safety properties:
#   - Only ever removes the GC2607-specific DKMS modules (gc2607,
#     ipu-bridge-gc2607, ipu6-drivers). It never touches other DKMS modules
#     such as sil6250 or v4l2loopback.
#   - Skips any /etc or /usr/src path that is owned by a pacman package: those
#     belong to an installed AUR package and must be removed with `pacman -R`,
#     not by hand. This makes the script safe to run after a partial migration.
#   - Every step is idempotent and tolerant of already-removed state.
set -uo pipefail

YES=0
[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && YES=1

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root: sudo $0 [-y]" >&2
    exit 1
fi

# The manual virtual-camera bits live in the invoking user's home, so resolve
# the real user behind sudo.
TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_HOME="${TARGET_HOME:-/root}"
USER_CONFIG="${TARGET_HOME}/.config"

# GC2607-specific DKMS modules only — never anything else.
DKMS_MODULES=(gc2607 ipu-bridge-gc2607 ipu6-drivers)

# System files the manual scripts dropped.
ETC_FILES=(
    /etc/modules-load.d/gc2607.conf
    /etc/modules-load.d/intel-ipu6-psys.conf
    /etc/modules-load.d/gc2607-v4l2loopback.conf
    /etc/modprobe.d/gc2607-v4l2loopback.conf
    /etc/udev/rules.d/70-ipu6-psys.rules
    /etc/v4l2-relayd.d/gc2607.conf
)

note()  { printf '  %s\n' "$*"; }
step()  { printf '\n==> %s\n' "$*"; }

# Echo the package owning $1, or empty if unowned by pacman.
pkg_owner() {
    pacman -Qoq "$1" 2>/dev/null || true
}

if [[ "$YES" -ne 1 ]]; then
    cat <<EOF
This will remove the *manual* GC2607 camera setup from this system:

  DKMS modules : ${DKMS_MODULES[*]}
  /usr/src     : gc2607-*, ipu-bridge-gc2607-*, ipu6-drivers-0.0.0 (manual only)
  /etc files   : ${ETC_FILES[*]}
  user config  : ${USER_CONFIG}/wireplumber/.../50-gc2607-virtual-camera.conf
                 ${USER_CONFIG}/systemd/user/gc2607-camera.service
  HAL build    : ${TARGET_HOME}/opt/gc2607-ipu6  $( [[ "${KEEP_HAL:-0}" == 1 ]] && echo '(kept: KEEP_HAL=1)' )

Pacman-owned files (from an installed AUR package) are left untouched.
Unrelated DKMS modules (sil6250, v4l2loopback) are left untouched.
EOF
    printf 'Proceed? [y/N] '
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# --- 1. Unload the live module stack (best effort) -----------------------
step "Unloading kernel modules (reverse dependency order)"
# gc2607 + the IPU6 stack must come out before the DKMS modules can be cleanly
# rebuilt/removed. Fails harmlessly if a camera app holds them open.
modprobe -r gc2607 intel_ipu6_isys intel_ipu6_psys intel_ipu6 ipu_bridge 2>/dev/null \
    && note "unloaded gc2607 + IPU6 stack" \
    || note "some modules still in use (a camera app may be open) — they will reload from the kernel copy"

# --- 2. Remove the GC2607 DKMS modules -----------------------------------
step "Removing DKMS modules"
for mod in "${DKMS_MODULES[@]}"; do
    # dkms status lines look like: "gc2607/0.3.1, <kernel>, x86_64: installed"
    mapfile -t versions < <(dkms status -m "$mod" 2>/dev/null \
        | sed -n "s#^${mod}/\([^,]*\),.*#\1#p" | sort -u)
    if [[ "${#versions[@]}" -eq 0 ]]; then
        note "$mod: not registered with DKMS"
        continue
    fi
    for ver in "${versions[@]}"; do
        dkms remove -m "$mod" -v "$ver" --all >/dev/null 2>&1 \
            && note "dkms remove $mod/$ver" \
            || note "dkms remove $mod/$ver (already gone)"
    done
done

# --- 3. Remove the /usr/src source trees / symlinks ----------------------
step "Removing /usr/src source trees"
shopt -s nullglob
for src in /usr/src/gc2607-* /usr/src/ipu-bridge-gc2607-* /usr/src/ipu6-drivers-0.0.0; do
    owner="$(pkg_owner "$src")"
    if [[ -n "$owner" ]]; then
        note "skip $src (owned by pacman package: $owner)"
        continue
    fi
    rm -rf "$src" && note "removed $src"
done
shopt -u nullglob

# --- 4. Remove the system config files -----------------------------------
step "Removing /etc config files"
for f in "${ETC_FILES[@]}"; do
    [[ -e "$f" ]] || continue
    owner="$(pkg_owner "$f")"
    if [[ -n "$owner" ]]; then
        note "skip $f (owned by pacman package: $owner)"
        continue
    fi
    rm -f "$f" && note "removed $f"
done

# --- 5. Remove the per-user virtual-camera integration -------------------
step "Removing user integration for '$TARGET_USER'"
WP_CONF="${USER_CONFIG}/wireplumber/wireplumber.conf.d/50-gc2607-virtual-camera.conf"
USER_UNIT="${USER_CONFIG}/systemd/user/gc2607-camera.service"

# Stop/disable the manual --user relayd engine service if present.
if [[ -e "$USER_UNIT" ]]; then
    runuser -u "$TARGET_USER" -- systemctl --user disable --now gc2607-camera.service 2>/dev/null || true
    rm -f "$USER_UNIT" && note "removed $USER_UNIT"
    runuser -u "$TARGET_USER" -- systemctl --user daemon-reload 2>/dev/null || true
else
    note "no user service unit"
fi

for f in "$WP_CONF" "${WP_CONF}.bak"; do
    [[ -e "$f" ]] && rm -f "$f" && note "removed $f"
done
# Restart WirePlumber so the hidden raw nodes reappear (best effort).
runuser -u "$TARGET_USER" -- systemctl --user try-restart wireplumber.service 2>/dev/null || true

# --- 6. Remove the in-$HOME HAL build ------------------------------------
HAL_BUILD="${TARGET_HOME}/opt/gc2607-ipu6"
if [[ "${KEEP_HAL:-0}" == 1 ]]; then
    step "Keeping HAL build ${HAL_BUILD} (KEEP_HAL=1)"
elif [[ -d "$HAL_BUILD" ]]; then
    step "Removing in-\$HOME HAL build"
    rm -rf "$HAL_BUILD" && note "removed $HAL_BUILD"
    rmdir "${TARGET_HOME}/opt" 2>/dev/null || true
fi

# --- 7. Reload kernel + udev state ---------------------------------------
step "Refreshing module + udev databases"
depmod -a 2>/dev/null || true
udevadm control --reload-rules 2>/dev/null || true

cat <<EOF

Done. The manual GC2607 setup has been removed.

Verify it is gone:
  dkms status | grep -E 'gc2607|ipu-bridge-gc2607|ipu6-drivers'   # (no output)
  ls /usr/src | grep -E 'gc2607|ipu6-drivers'                     # (no output)

Now install the packaged stack (see packaging/aur/README.md):
  cd packaging/aur
  (cd gc2607-dkms && makepkg -si) && ... && (cd gc2607-virtual-camera && makepkg -si)
  reboot
EOF
