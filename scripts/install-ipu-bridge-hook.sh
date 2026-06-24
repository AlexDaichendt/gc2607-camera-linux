#!/usr/bin/env bash
# Install the pacman hook that auto-rebuilds the GC2607 ipu-bridge override on
# every kernel install/upgrade, so the camera survives kernel bumps.
#
# Installs:
#   /usr/local/lib/gc2607/rebuild-ipu-bridge-override.sh  (rebuild logic)
#   /usr/local/lib/gc2607/ipu-bridge.c                    (vendored fallback src)
#   /etc/pacman.d/hooks/90-gc2607-ipu-bridge.hook         (trigger)
#
# Also rebuilds the override for the currently running kernel right away.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBDIR="/usr/local/lib/gc2607"
HOOKDIR="/etc/pacman.d/hooks"

SRC_SCRIPT="$ROOT/scripts/rebuild-ipu-bridge-override.sh"
SRC_BRIDGE="$ROOT/bridge/ipu-bridge.c"
SRC_HOOK="$ROOT/config/pacman/hooks/90-gc2607-ipu-bridge.hook"

for f in "$SRC_SCRIPT" "$SRC_BRIDGE" "$SRC_HOOK"; do
    [[ -f "$f" ]] || { echo "Missing source file: $f" >&2; exit 1; }
done

sudo install -D -m 0755 "$SRC_SCRIPT" "$LIBDIR/rebuild-ipu-bridge-override.sh"
sudo install -D -m 0644 "$SRC_BRIDGE" "$LIBDIR/ipu-bridge.c"
sudo install -D -m 0644 "$SRC_HOOK"   "$HOOKDIR/90-gc2607-ipu-bridge.hook"

echo "Installed pacman hook and rebuild helper under $LIBDIR."
echo "Rebuilding override for the running kernel ($(uname -r))..."
sudo "$LIBDIR/rebuild-ipu-bridge-override.sh"

cat <<EOF

Done. On the next kernel install/upgrade, pacman will rebuild and install the
GC2607 ipu-bridge override automatically (requires that kernel's linux-headers).

Verify after a kernel bump and reboot:
  modinfo ipu-bridge | grep -E 'filename|vermagic'
  media-ctl --print-topology | grep -i gc2607
EOF
