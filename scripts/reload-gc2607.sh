#!/usr/bin/env bash
#
# reload-gc2607.sh - rebuild the DKMS module and hot-reload it on the IPU6 stack.
#
# The gc2607 subdev is held by intel-ipu6-isys once probed, so it can't be
# rmmod'd on its own. This tears down the ISYS/IPU6 stack, swaps the module,
# brings the pipeline back up, and (optionally) streams a few frames to check
# fps. Run as root.
#
# Usage:
#   sudo ./scripts/reload-gc2607.sh            # dkms rebuild + reload + fps check
#   sudo ./scripts/reload-gc2607.sh --no-build # reload the already-installed module
#   sudo FRAMES=0 ./scripts/reload-gc2607.sh   # reload only, skip the fps capture
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIDEO="${VIDEO:-/dev/video0}"
MEDIA="${MEDIA:-/dev/media0}"
FRAMES="${FRAMES:-150}"
CSI_LINK='"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0'

if [[ "$(id -u)" -ne 0 ]]; then
	echo "Run as root (needs modprobe/rmmod/media-ctl)." >&2
	exit 1
fi

if [[ "${1:-}" != "--no-build" ]]; then
	echo "== Rebuilding + installing DKMS module =="
	"$ROOT/scripts/install-gc2607-dkms.sh"
fi

echo "== Tearing down IPU6 stack and unloading gc2607 =="
pkill -f "gst-launch.*video" 2>/dev/null || true
media-ctl -d "$MEDIA" -l "${CSI_LINK}[0]" 2>/dev/null || true
modprobe -r intel-ipu6-isys 2>/dev/null || true
modprobe -r intel-ipu6 2>/dev/null || true
modprobe -r gc2607 2>/dev/null || true
sleep 1

echo "== Reloading =="
modprobe videodev
modprobe v4l2-async
modprobe gc2607
modprobe intel-ipu6
modprobe intel-ipu6-isys
sleep 1

echo "== Bringing up the raw ISYS pipeline =="
media-ctl -d "$MEDIA" -V '"Intel IPU6 CSI2 0":0 [fmt:SGRBG10_1X10/1920x1080]' 2>/dev/null || true
media-ctl -d "$MEDIA" -V '"Intel IPU6 CSI2 0":1 [fmt:SGRBG10_1X10/1920x1080]' 2>/dev/null || true
v4l2-ctl -d "$VIDEO" --set-fmt-video=width=1920,height=1080,pixelformat=BA10 >/dev/null 2>&1 || true
media-ctl -d "$MEDIA" -l "${CSI_LINK}[1]" 2>/dev/null || true

echo "== Loaded module =="
modinfo gc2607 2>/dev/null | grep -E '^(filename|version|description)' || true

if [[ "$FRAMES" -gt 0 ]]; then
	echo "== Streaming $FRAMES frames =="
	timeout 30 v4l2-ctl -d "$VIDEO" --stream-mmap \
		--stream-count="$FRAMES" --stream-to=/dev/null 2>&1 \
		| grep -oE '[0-9]+\.[0-9]+ fps' | tail -1 || echo "no fps reported"
fi

echo "Done. Check 'dmesg | tail' for gc2607 probe messages."
