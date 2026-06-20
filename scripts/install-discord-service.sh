#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install -D -m 0755 \
    "$ROOT/scripts/gc2607-discord-camera.sh" \
    "$HOME/bin/gc2607-discord-camera.sh"

install -D -m 0644 \
    "$ROOT/systemd/user/gc2607-discord-camera.service" \
    "$HOME/.config/systemd/user/gc2607-discord-camera.service"

systemctl --user daemon-reload
systemctl --user enable gc2607-discord-camera.service

cat <<EOF
Installed user service:
  gc2607-discord-camera.service

Start it when needed:
  systemctl --user start gc2607-discord-camera.service

Stop it after calls:
  systemctl --user stop gc2607-discord-camera.service

The loopback device still needs one-time sudo setup:
  sudo cp "$ROOT/config/modprobe.d/gc2607-loopback.conf" /etc/modprobe.d/
  sudo cp "$ROOT/config/modules-load.d/gc2607-loopback.conf" /etc/modules-load.d/
  sudo modprobe v4l2loopback
EOF
