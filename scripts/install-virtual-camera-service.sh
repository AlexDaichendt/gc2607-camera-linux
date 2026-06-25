#!/usr/bin/env bash
set -euo pipefail

# Make the GC2607 virtual camera survive reboots, end to end:
#
#   1. v4l2loopback auto-loads at boot with the right options, so
#      /dev/video60 ("GC2607 Virtual Camera") exists before the user logs in.
#   2. A systemd --user service runs the on-demand watcher
#      (virtual-camera.sh watch-foreground): the real GC2607 sensor only spins
#      up while an app is actually using the virtual device, then idles off.
#   3. The WirePlumber desktop integration is installed so apps prefer the
#      virtual camera and the raw IPU6 nodes stay hidden.
#
# Re-runnable: every step is idempotent.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VIDEO_NR="${GC2607_VCAM_VIDEO_NR:-60}"
LABEL="${GC2607_VCAM_LABEL:-GC2607 Virtual Camera}"
EXCLUSIVE_CAPS="${GC2607_VCAM_EXCLUSIVE_CAPS:-1}"
MAX_BUFFERS="${GC2607_VCAM_MAX_BUFFERS:-2}"

UNIT_NAME="gc2607-camera"
UNIT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/${UNIT_NAME}.service"

MODULES_LOAD_CONF="/etc/modules-load.d/gc2607-v4l2loopback.conf"
MODPROBE_CONF="/etc/modprobe.d/gc2607-v4l2loopback.conf"

echo "==> Installing v4l2loopback auto-load drop-ins (sudo)"

sudo install -m 0644 /dev/stdin "$MODULES_LOAD_CONF" <<EOF
# Auto-load the v4l2loopback module at boot for the GC2607 virtual camera.
v4l2loopback
EOF
echo "    wrote $MODULES_LOAD_CONF"

sudo install -m 0644 /dev/stdin "$MODPROBE_CONF" <<EOF
# Options for the GC2607 virtual camera loopback device.
# Keep these in sync with scripts/virtual-camera.sh (ensure_loopback).
options v4l2loopback devices=1 video_nr=${VIDEO_NR} card_label="${LABEL}" exclusive_caps=${EXCLUSIVE_CAPS} max_buffers=${MAX_BUFFERS}
EOF
echo "    wrote $MODPROBE_CONF"

echo "==> Installing WirePlumber desktop integration"
"$ROOT/scripts/install-virtual-camera-desktop.sh"

echo "==> Installing systemd --user watcher service"
mkdir -p "$(dirname "$UNIT_FILE")"
install -m 0644 /dev/stdin "$UNIT_FILE" <<EOF
[Unit]
Description=GC2607 on-demand virtual camera watcher
Documentation=https://github.com/AlexDaichendt/gc2607-camera-linux
# The real sensor and PipeWire registration both need the graphical user
# session's media stack to be up first.
After=pipewire.service wireplumber.service
Wants=pipewire.service wireplumber.service

[Service]
Type=simple
ExecStart=${ROOT}/scripts/virtual-camera.sh watch-foreground
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
echo "    wrote $UNIT_FILE"

systemctl --user daemon-reload
systemctl --user enable --now "${UNIT_NAME}.service"

echo
echo "Done. The GC2607 virtual camera is now persistent across reboots."
echo "  - v4l2loopback auto-loads at boot (/dev/video${VIDEO_NR} = '${LABEL}')"
echo "  - ${UNIT_NAME}.service arms the on-demand watcher on login"
echo
echo "Check status with: scripts/virtual-camera.sh status"
