#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d"
CONFIG_FILE="$CONFIG_DIR/50-gc2607-virtual-camera.conf"
BACKUP_FILE="$CONFIG_FILE.bak"

mkdir -p "$CONFIG_DIR"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

cat >"$tmp" <<'EOF'
# GC2607 virtual-camera desktop integration.
#
# The calibrated Intel HAL path is exported as a v4l2loopback webcam. Hide the
# raw IPU6 V4L2 nodes and the uncalibrated libcamera GC2607 source from
# WirePlumber so chat apps pick the virtual camera and do not keep /dev/video0
# busy.

wireplumber.profiles = {
  main = {
    monitor.libcamera = disabled
  }
}

monitor.libcamera.rules = [
  {
    matches = [
      {
        device.product.name = "gc2607"
      }
    ]
    actions = {
      update-props = {
        device.disabled = true
        node.disabled = true
      }
    }
  }
]

monitor.v4l2.rules = [
  {
    matches = [
      {
        api.v4l2.cap.driver = "isys"
      }
    ]
    actions = {
      update-props = {
        device.disabled = true
        node.disabled = true
      }
    }
  },
  {
    matches = [
      {
        api.v4l2.cap.driver = "v4l2 loopback"
        api.v4l2.cap.card = "GC2607 Virtual Camera"
      }
    ]
    actions = {
      update-props = {
        node.description = "GC2607 Virtual Camera"
        node.nick = "GC2607 Virtual Camera"
        priority.session = 1200
      }
    }
  }
]
EOF

if [[ -e "$CONFIG_FILE" ]] && ! cmp -s "$CONFIG_FILE" "$tmp"; then
    cp -a "$CONFIG_FILE" "$BACKUP_FILE"
    echo "Backed up existing config to $BACKUP_FILE"
fi

install -m 0644 "$tmp" "$CONFIG_FILE"
echo "Installed $CONFIG_FILE"

if systemctl --user is-active --quiet wireplumber.service; then
    systemctl --user restart wireplumber.service
    echo "Restarted wireplumber.service"
else
    echo "wireplumber.service is not active; config will apply when it starts."
fi

cat <<EOF

Next:
  scripts/virtual-camera.sh prepare
  scripts/virtual-camera.sh start
EOF
