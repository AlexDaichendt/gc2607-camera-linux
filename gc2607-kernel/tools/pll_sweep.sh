#!/bin/bash
#
# pll_sweep.sh - bisect GC2607 PLL/timing registers on hardware.
#
# For each test point it reloads gc2607.ko with the given module params,
# brings up the IPU6 raw-ISYS pipeline (/dev/video0, BA10, no ISP/3A), streams
# N frames, records the measured fps, and scans dmesg for PLL/CSI/IPU errors.
# Results are appended to a CSV so you can see fps + stability per register set.
#
# A "point" is "LABEL:insmod-args".  Empty args == stock build (control).
#
# Usage (Windows-derived 30fps target — see tools/PLL_SWEEP.md):
#   sudo ./tools/pll_sweep.sh \
#       "stock:" \
#       "win30:reg0135=0x05 reg0136=0x42 reg031c=0xf3 hts=2745 vts=1250 frame_len=1250"
#
# Then read results.csv.  Bisect reg0134 toward the value that gives ~30 fps
# WITHOUT CSI errors in the dmesg column.  If raising reg0134 lifts fps but
# breaks CSI lock, the MIPI clock rose too: bump a divider (reg0315/reg031c)
# back down in the same point to keep the link <= 672 Mbps.
#
set -u

# ---- config (override via env) ----------------------------------------------
KO="${KO:-$(cd "$(dirname "$0")/.." && pwd)/gc2607.ko}"
VIDEO="${VIDEO:-/dev/video0}"
MEDIA="${MEDIA:-/dev/media0}"
FRAMES="${FRAMES:-150}"
OUT="${OUT:-results.csv}"
CSI_LINK='"Intel IPU6 CSI2 0":1 -> "Intel IPU6 ISYS Capture 0":0'

if [[ $EUID -ne 0 ]]; then
	echo "Run as root (needs insmod/rmmod/media-ctl)." >&2
	exit 1
fi
if [[ ! -f "$KO" ]]; then
	echo "Module not found: $KO  (build it first: make LLVM=1)" >&2
	exit 1
fi
if [[ $# -eq 0 ]]; then
	echo "No test points given. See header for usage." >&2
	exit 1
fi

reload() {		# $1 = insmod args
	pkill -f "gst-launch.*video" 2>/dev/null || true
	media-ctl -d "$MEDIA" -l "${CSI_LINK}[0]" 2>/dev/null || true
	modprobe -r intel-ipu6-isys 2>/dev/null || true
	modprobe -r intel-ipu6 2>/dev/null || true
	rmmod gc2607 2>/dev/null || true
	sleep 1
	modprobe videodev; modprobe v4l2-async
	modprobe intel-ipu6; modprobe intel-ipu6-isys
	sleep 1
	# shellcheck disable=SC2086
	insmod "$KO" $1 || { echo "insmod failed"; return 1; }
	sleep 1
	media-ctl -d "$MEDIA" -V '"Intel IPU6 CSI2 0":0 [fmt:SGRBG10_1X10/1920x1080]' 2>/dev/null
	media-ctl -d "$MEDIA" -V '"Intel IPU6 CSI2 0":1 [fmt:SGRBG10_1X10/1920x1080]' 2>/dev/null
	v4l2-ctl -d "$VIDEO" --set-fmt-video=width=1920,height=1080,pixelformat=BA10 >/dev/null 2>&1
	media-ctl -d "$MEDIA" -l "${CSI_LINK}[1]" 2>/dev/null
}

measure_fps() {		# stream FRAMES, echo last "NN.NN fps" or "FAIL"
	local out
	out=$(timeout 30 v4l2-ctl -d "$VIDEO" --stream-mmap \
		--stream-count="$FRAMES" --stream-to=/dev/null 2>&1)
	echo "$out" | grep -oE '[0-9]+\.[0-9]+ fps' | tail -1 | grep -oE '^[0-9.]+' \
		|| echo "FAIL"
}

scan_errors() {		# $1 = dmesg cursor (line count before reload)
	dmesg | tail -n +"$(( $1 + 1 ))" \
		| grep -iE 'gc2607|ipu6|csi|pll|error|fail|timeout|fmt' \
		| grep -iE 'error|fail|timeout|mismatch|not lock|underrun' \
		| head -3 | tr '\n' ';' | tr ',' ';'
}

[[ -f "$OUT" ]] || echo "timestamp,label,args,fps,errors" > "$OUT"
printf '%-12s %-28s %-8s %s\n' LABEL ARGS FPS ERRORS

for point in "$@"; do
	label="${point%%:*}"
	args="${point#*:}"
	cursor=$(dmesg | wc -l)
	if ! reload "$args"; then
		printf '%-12s %-28s %-8s %s\n' "$label" "$args" "RELOAD" "insmod/setup failed"
		echo "$(date -Is),$label,\"$args\",RELOAD_FAIL," >> "$OUT"
		continue
	fi
	fps=$(measure_fps)
	errs=$(scan_errors "$cursor")
	printf '%-12s %-28s %-8s %s\n' "$label" "$args" "$fps" "${errs:-clean}"
	echo "$(date -Is),$label,\"$args\",$fps,\"$errs\"" >> "$OUT"
done

echo
echo "Full log: $OUT"
echo "Reminder: 30.00 fps with an empty errors column == win."
