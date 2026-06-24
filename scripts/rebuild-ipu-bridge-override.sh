#!/usr/bin/env bash
# Rebuild and install the GC2607-patched ipu-bridge override module so the IPU6
# camera keeps working across kernel upgrades.
#
# The distro kernel ships an in-tree ipu-bridge that does NOT know about the
# GalaxyCore GC2607 (ACPI HID GCTI2607). Without a patched override the sensor
# enumerates on i2c but never gets wired into the IPU6 CSI-2 media graph, so the
# camera silently breaks on every kernel bump. This script rebuilds the override
# for a given kernel and installs it into that kernel's updates/ directory.
#
# Usage:
#   rebuild-ipu-bridge-override.sh [KVER ...]   # rebuild for these kernel releases
#   rebuild-ipu-bridge-override.sh              # default: $(uname -r)
#   rebuild-ipu-bridge-override.sh --pacman-targets
#                                               # read usr/lib/modules/*/pkgbase
#                                               # lines from stdin (pacman hook mode)
#
# Must run as root (installs into /lib/modules/<kver>/updates).
#
# Environment overrides:
#   IPU_BRIDGE_SRC     path to an ipu-bridge.c to use instead of the vendored copy
#   IPU_BRIDGE_FETCH=1 fetch the matching-version ipu-bridge.c from git.kernel.org
#                      instead of using the vendored copy (auto-tried as a fallback
#                      if the vendored source fails to build)
#   IPU_BRIDGE_MOK_KEY / IPU_BRIDGE_MOK_CRT
#                      module-signing key/cert (default: DKMS MOK if present)
set -euo pipefail

HID="GCTI2607"
LINK_FREQ="336000000"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STABLE_BASE="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/media/pci/intel/ipu-bridge.c"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'rebuild-ipu-bridge: %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "must run as root (installs into /lib/modules/<kver>/updates)"

# Locate the vendored fallback source: repo checkout layout, then the installed
# layout where the .c sits next to this script.
vendored_src() {
    local c
    for c in "${IPU_BRIDGE_SRC:-}" "$SELF/../bridge/ipu-bridge.c" "$SELF/ipu-bridge.c"; do
        [[ -n "$c" && -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
    done
    return 1
}

# Map a uname release to the stable git tag, e.g. 7.0.10-arch1-1 -> v7.0.10.
stable_tag() {
    printf 'v%s\n' "${1%%-*}"
}

# Ensure the GC2607 sensor entry is present in the bridge sensor table (idempotent).
ensure_hid_entry() {
    local file="$1"
    if grep -q "\"$HID\"" "$file"; then
        return 0
    fi
    # Insert right after the sensor table declaration so it builds regardless of
    # the surrounding entries.
    local anchor='static const struct ipu_sensor_config ipu_supported_sensors\[\] = {'
    grep -q "$anchor" "$file" || die "could not find sensor table in $file"
    sed -i "/$anchor/a\\
\\t/* GalaxyCore GC2607 */\\
\\tIPU_SENSOR_CONFIG(\"$HID\", 1, $LINK_FREQ)," "$file"
    grep -q "\"$HID\"" "$file" || die "failed to insert $HID entry into $file"
}

fetch_src() {
    local kver="$1" dest="$2" tag
    tag="$(stable_tag "$kver")"
    command -v curl >/dev/null 2>&1 || return 1
    log "fetching ipu-bridge.c for $tag from git.kernel.org"
    curl -fsSL "${STABLE_BASE}?h=${tag}" -o "$dest" 2>/dev/null || return 1
    [[ -s "$dest" ]] && grep -q ipu_supported_sensors "$dest"
}

# Compile a prepared ipu-bridge.c into ipu-bridge.ko for $kver in $work.
compile_src() {
    local kver="$1" work="$2" kbuild="/lib/modules/$kver/build"
    printf 'obj-m := ipu-bridge.o\n' > "$work/Makefile"
    make -C "$kbuild" M="$work" modules >"$work/build.log" 2>&1
}

sign_module() {
    local kver="$1" ko="$2"
    local key="${IPU_BRIDGE_MOK_KEY:-/var/lib/dkms/mok.key}"
    local crt="${IPU_BRIDGE_MOK_CRT:-/var/lib/dkms/mok.pub}"
    local signer="/lib/modules/$kver/build/scripts/sign-file"
    if [[ -x "$signer" && -f "$key" && -f "$crt" ]]; then
        "$signer" sha256 "$key" "$crt" "$ko" 2>/dev/null \
            && log "signed with MOK ($key)" \
            || warn "signing failed; module installed unsigned (ok if sig_enforce=N)"
    else
        log "no MOK key/sign-file; installing unsigned (ok if sig_enforce=N)"
    fi
}

rebuild_one() {
    local kver="$1"
    local kbuild="/lib/modules/$kver/build"
    local dest="/lib/modules/$kver/updates/ipu-bridge.ko"

    if [[ ! -d "$kbuild" ]]; then
        warn "skip $kver: kernel build tree missing ($kbuild); install its linux-headers"
        return 0
    fi

    # Idempotent: skip when a good override is already in place.
    if [[ -f "$dest" ]] \
        && strings "$dest" 2>/dev/null | grep -q "$HID" \
        && modinfo -F vermagic "$dest" 2>/dev/null | grep -q "^$kver "; then
        log "$kver: override already current ($HID present, vermagic ok)"
        return 0
    fi

    local work
    work="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$work'" RETURN

    local src
    if [[ "${IPU_BRIDGE_FETCH:-0}" == "1" ]]; then
        fetch_src "$kver" "$work/ipu-bridge.c" || die "$kver: fetch failed and IPU_BRIDGE_FETCH=1"
    else
        src="$(vendored_src)" || die "no vendored ipu-bridge.c found (set IPU_BRIDGE_SRC)"
        cp "$src" "$work/ipu-bridge.c"
    fi
    ensure_hid_entry "$work/ipu-bridge.c"

    log "$kver: building ipu-bridge override"
    if ! compile_src "$kver" "$work"; then
        # Vendored source may not match a newer kernel's bridge ABI. Try the
        # matching-version upstream source before giving up.
        if [[ "${IPU_BRIDGE_FETCH:-0}" != "1" ]] && fetch_src "$kver" "$work/ipu-bridge.c"; then
            ensure_hid_entry "$work/ipu-bridge.c"
            log "$kver: retrying build with matching upstream source"
            compile_src "$kver" "$work" || { cat "$work/build.log" >&2; die "$kver: build failed"; }
        else
            cat "$work/build.log" >&2
            die "$kver: build failed (vendored source incompatible; network fetch unavailable)"
        fi
    fi

    [[ -f "$work/ipu-bridge.ko" ]] || die "$kver: build produced no ipu-bridge.ko"

    sign_module "$kver" "$work/ipu-bridge.ko"

    install -D -m 0644 "$work/ipu-bridge.ko" "$dest"
    depmod -a "$kver"
    log "$kver: installed -> $dest"
}

# --- argument handling --------------------------------------------------------

kvers=()
if [[ "${1:-}" == "--pacman-targets" ]]; then
    # Read lines like "usr/lib/modules/7.0.11-arch1-1/pkgbase" from stdin.
    while read -r line; do
        kver="${line#*lib/modules/}"
        kver="${kver%%/*}"
        [[ -n "$kver" ]] && kvers+=("$kver")
    done
elif [[ $# -gt 0 ]]; then
    kvers=("$@")
else
    kvers=("$(uname -r)")
fi

[[ ${#kvers[@]} -gt 0 ]] || { log "no target kernels; nothing to do"; exit 0; }

for kver in "${kvers[@]}"; do
    rebuild_one "$kver"
done
