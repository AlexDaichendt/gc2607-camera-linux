#!/usr/bin/env bash
#
# reload-gc2607.sh - build and hot-reload the gc2607 module on the IPU6 stack.
#
# By default this builds with plain `make` and loads via insmod — no DKMS, no
# version bumps needed. Use --dkms when you want a persistent install that
# survives kernel upgrades.
#
# Usage:
#   sudo ./scripts/reload-gc2607.sh              # make + insmod + fps check
#   sudo ./scripts/reload-gc2607.sh --no-build   # insmod already-built .ko
#   sudo ./scripts/reload-gc2607.sh --dkms       # DKMS install + modprobe
#   sudo FRAMES=0 ./scripts/reload-gc2607.sh     # reload only, skip fps capture
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="$ROOT/gc2607-kernel"
# VIDEO/MEDIA are auto-detected after the IPU6 stack loads (node numbers move
# across reloads and /dev/video0 is often the UVC webcam, not ISYS). Set the
# env vars to override.
VIDEO="${VIDEO:-}"
MEDIA="${MEDIA:-}"
FRAMES="${FRAMES:-150}"
CAPTURE_ENTITY="Intel IPU6 ISYS Capture 0"
CSI_LINK="\"Intel IPU6 CSI2 0\":1 -> \"${CAPTURE_ENTITY}\":0"

# Echo the /dev/mediaN whose driver is intel-ipu6 (the gc2607 graph), or nothing.
detect_media() {
    local m
    for m in /dev/media*; do
        [[ -e "$m" ]] || continue
        if media-ctl -d "$m" -p 2>/dev/null | grep -qE '^driver[[:space:]]+intel-ipu6$'; then
            echo "$m"
            return 0
        fi
    done
    return 1
}

MODE=dev   # dev | dkms
BUILD=1

for arg in "$@"; do
    case "$arg" in
        --dkms)     MODE=dkms ;;
        --no-build) BUILD=0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root (needs modprobe/rmmod/insmod/media-ctl)." >&2
    exit 1
fi

if [[ "$MODE" == "dkms" ]]; then
    if [[ "$BUILD" -eq 1 ]]; then
        echo "== Rebuilding + installing via DKMS =="
        "$ROOT/scripts/install-gc2607-dkms.sh"
    fi
else
    if [[ "$BUILD" -eq 1 ]]; then
        echo "== Building gc2607.ko =="
        make -C "$DRIVER"
    fi
    KO="$DRIVER/gc2607.ko"
    if [[ ! -f "$KO" ]]; then
        echo "Module not found: $KO  (run without --no-build to build first)" >&2
        exit 1
    fi
fi

echo "== Tearing down IPU6 stack and unloading gc2607 =="
pkill -f "gst-launch.*video" 2>/dev/null || true
TEARDOWN_MEDIA="${MEDIA:-$(detect_media || true)}"
[[ -n "$TEARDOWN_MEDIA" ]] && media-ctl -d "$TEARDOWN_MEDIA" -l "${CSI_LINK}[0]" 2>/dev/null || true
modprobe -r intel-ipu6-isys 2>/dev/null || true
modprobe -r intel-ipu6 2>/dev/null || true
rmmod gc2607 2>/dev/null || modprobe -r gc2607 2>/dev/null || true
sleep 1

echo "== Reloading =="
modprobe videodev
modprobe v4l2-async
modprobe v4l2-fwnode
modprobe v4l2-cci
if [[ "$MODE" == "dkms" ]]; then
    modprobe gc2607
else
    insmod "$KO"
fi
modprobe intel-ipu6
modprobe intel-ipu6-isys
sleep 1

echo "== Detecting IPU6 media + ISYS capture nodes =="
[[ -z "$MEDIA" ]] && MEDIA="$(detect_media || true)"
if [[ -z "$MEDIA" ]]; then
    echo "Could not find an intel-ipu6 media device (is intel-ipu6-isys loaded?)." >&2
    exit 1
fi
if [[ -z "$VIDEO" ]]; then
    VIDEO="$(media-ctl -d "$MEDIA" -e "$CAPTURE_ENTITY" 2>/dev/null)"
fi
if [[ -z "$VIDEO" || ! -e "$VIDEO" ]]; then
    echo "Could not resolve '$CAPTURE_ENTITY' to a /dev/video node on $MEDIA." >&2
    exit 1
fi
echo "   MEDIA=$MEDIA  VIDEO=$VIDEO"

echo "== Bringing up the raw ISYS pipeline =="
media-ctl -d "$MEDIA" -V '"Intel IPU6 CSI2 0":0 [fmt:SGRBG10_1X10/1920x1080]' 2>/dev/null || true
media-ctl -d "$MEDIA" -V '"Intel IPU6 CSI2 0":1 [fmt:SGRBG10_1X10/1920x1080]' 2>/dev/null || true
if ! v4l2-ctl -d "$VIDEO" --set-fmt-video=width=1920,height=1080,pixelformat=BA10; then
    echo "Warning: failed to set BA10/1920x1080 on $VIDEO; fps probe may fail." >&2
fi
media-ctl -d "$MEDIA" -l "${CSI_LINK}[1]" 2>/dev/null || true

echo "== Loaded module =="
if [[ "$MODE" == "dkms" ]]; then
    modinfo gc2607 2>/dev/null | grep -E '^(filename|version|description)' || true
else
    modinfo "$KO" 2>/dev/null | grep -E '^(filename|version|description)' || true
fi

if [[ "$FRAMES" -gt 0 ]]; then
    echo "== Streaming $FRAMES frames =="
    timeout 30 v4l2-ctl -d "$VIDEO" --stream-mmap \
        --stream-count="$FRAMES" --stream-to=/dev/null 2>&1 \
        | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1 || echo "no fps reported"
fi

echo "Done. Check 'dmesg | tail' for gc2607 probe messages."
