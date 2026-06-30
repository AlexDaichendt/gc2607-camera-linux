#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UNIT_NAME="${GC2607_VCAM_UNIT_NAME:-gc2607-virtual-camera}"
UNIT="${UNIT_NAME}.service"
VIDEO_NR="${GC2607_VCAM_VIDEO_NR:-60}"
DEVICE="${GC2607_VCAM_DEVICE:-/dev/video${VIDEO_NR}}"
LABEL="${GC2607_VCAM_LABEL:-GC2607 Virtual Camera}"
EXCLUSIVE_CAPS="${GC2607_VCAM_EXCLUSIVE_CAPS:-1}"
MAX_BUFFERS="${GC2607_VCAM_MAX_BUFFERS:-2}"
RAW_DEVICE="${GC2607_RAW_DEVICE:-/dev/video0}"

if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

usage() {
    cat <<EOF
Usage: $(basename "$0") COMMAND

Commands:
  prepare   Create/refresh the virtual webcam without powering the real camera
  register  Refresh PipeWire visibility for the virtual device
  start     Start the relayd engine; the real camera powers on only while used
  stop      Stop the relayd engine
  status    Show engine and virtual device state
  logs      Show recent relayd logs
  run       Run the relayd engine in the foreground
  unload    Stop the engine and unload v4l2loopback

Environment:
  GC2607_VCAM_VIDEO_NR       video node number, default: 60
  GC2607_VCAM_LABEL          loopback card label, default: GC2607 Virtual Camera
  GC2607_VCAM_WIDTH          output width, default: 1280
  GC2607_VCAM_HEIGHT         output height, default: 720
  GC2607_VCAM_FRAMERATE      output framerate, default: 30/1
  GC2607_VCAM_FORMAT         output format, default: YUY2
  GC2607_VCAM_MAX_RUNTIME    optional systemd RuntimeMaxSec, for example 90min
  GC2607_RAW_DEVICE          raw IPU6 capture node to check, default: /dev/video0
  GC2607_RELAYD_DEBUG        set to enable relayd -d debug logging
EOF
}

video_name() {
    local video="$1"
    local base
    base="$(basename "$video")"
    cat "/sys/class/video4linux/${base}/name" 2>/dev/null || true
}

find_labelled_device() {
    local path name base

    for path in /sys/devices/virtual/video4linux/video*/name; do
        [[ -e "$path" ]] || continue
        name="$(cat "$path" 2>/dev/null || true)"
        if [[ "$name" == "$LABEL" ]]; then
            base="$(basename "$(dirname "$path")")"
            printf '/dev/%s\n' "$base"
            return 0
        fi
    done

    return 1
}

ensure_configured_device_is_free() {
    local current_name

    if [[ ! -e "$DEVICE" ]]; then
        return 0
    fi

    current_name="$(video_name "$DEVICE")"
    if [[ "$current_name" == "$LABEL" ]]; then
        return 0
    fi

    echo "$DEVICE already exists and is named '$current_name', not '$LABEL'." >&2
    echo "Set GC2607_VCAM_VIDEO_NR to a free node number and retry." >&2
    exit 1
}

ensure_loopback() {
    local found

    if found="$(find_labelled_device)"; then
        DEVICE="$found"
        return 0
    fi

    ensure_configured_device_is_free

    if lsmod | rg -q '^v4l2loopback\b'; then
        echo "v4l2loopback is already loaded, but '$LABEL' was not found." >&2
        echo "Without v4l2loopback-ctl, this script cannot add another loopback device dynamically." >&2
        echo "Stop other loopback users, unload the module, or set GC2607_VCAM_VIDEO_NR to an existing labelled device." >&2
        exit 1
    fi

    sudo modprobe v4l2loopback \
        devices=1 \
        "video_nr=$VIDEO_NR" \
        "card_label=$LABEL" \
        "exclusive_caps=$EXCLUSIVE_CAPS" \
        "max_buffers=$MAX_BUFFERS"

    if command -v udevadm >/dev/null 2>&1; then
        udevadm settle || true
    fi

    if ! found="$(find_labelled_device)"; then
        echo "Loaded v4l2loopback, but could not find '$LABEL'." >&2
        exit 1
    fi

    DEVICE="$found"
}

pipewire_has_virtual_source() {
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
        pw-cli ls Node 2>/dev/null | rg -q "object.path = \"v4l2:${DEVICE}\""
}

add_common_systemd_env() {
    local -n out="$1"
    local var

    out+=(
        --setenv="GC2607_VCAM_DEVICE=$DEVICE"
        --setenv="GC2607_VCAM_VIDEO_NR=$VIDEO_NR"
        --setenv="GC2607_VCAM_LABEL=$LABEL"
        --setenv="GC2607_RAW_DEVICE=$RAW_DEVICE"
    )

    for var in \
        GC2607_PREFIX \
        GC2607_RELAYD_BIN \
        GC2607_RELAYD_DEBUG \
        GC2607_FLIP_METHOD \
        GC2607_AE_MODE \
        GC2607_EXPOSURE_TIME \
        GC2607_GAIN \
        GC2607_VCAM_SOURCE_WIDTH \
        GC2607_VCAM_SOURCE_HEIGHT \
        GC2607_VCAM_WIDTH \
        GC2607_VCAM_HEIGHT \
        GC2607_VCAM_FRAMERATE \
        GC2607_VCAM_FORMAT \
        GC2607_VCAM_SPLASHSRC \
        GC2607_VCAM_MAX_RUNTIME; do
        if [[ -n "${!var+x}" ]]; then
            out+=(--setenv="$var=${!var}")
        fi
    done
}

register_pipewire_source() {
    local registered=0

    ensure_loopback

    if pipewire_has_virtual_source; then
        echo "PipeWire source registered for $DEVICE."
        return 0
    fi

    if systemctl --user is-active --quiet wireplumber.service; then
        systemctl --user restart wireplumber.service
    fi

    for _ in {1..20}; do
        if pipewire_has_virtual_source; then
            registered=1
            break
        fi
        sleep 0.25
    done

    if [[ "$registered" == 1 ]] || pipewire_has_virtual_source; then
        echo "PipeWire source registered for $DEVICE."
    else
        echo "Virtual device exists, but PipeWire did not expose a Video/Source yet." >&2
        echo "Run scripts/install-virtual-camera-desktop.sh, then retry prepare." >&2
        return 1
    fi
}

release_raw_camera() {
    if [[ ! -e "$RAW_DEVICE" ]]; then
        return 0
    fi

    if fuser -s "$RAW_DEVICE" 2>/dev/null; then
        echo "$RAW_DEVICE is open; restarting WirePlumber to release stale camera users."
        systemctl --user restart wireplumber.service >/dev/null 2>&1 || true
        sleep 1
    fi

    if fuser -s "$RAW_DEVICE" 2>/dev/null; then
        echo "$RAW_DEVICE is still busy. Current users:" >&2
        fuser -v "$RAW_DEVICE" >&2 || true
        echo >&2
        echo "Close camera previews/calls that selected the built-in GC2607 source." >&2
        echo "For Telegram, close the camera settings/call window or quit and reopen Telegram." >&2
        echo "If WirePlumber is listed, run scripts/install-virtual-camera-desktop.sh once." >&2
        return 1
    fi
}

start_engine() {
    local args=()

    ensure_loopback
    register_pipewire_source || true

    if systemctl --user is-active --quiet "$UNIT"; then
        echo "$UNIT is already active."
        echo "Virtual camera: $DEVICE"
        return 0
    fi

    # relayd opens the real sensor lazily, but a stale holder on the raw node
    # would still make the first consumer fail, so clear it up front.
    release_raw_camera || true

    args=(
        --user
        --unit="$UNIT_NAME"
        --description="GC2607 virtual camera relayd engine"
        --collect
        --same-dir
        --property=Restart=on-failure
        --property=RestartSec=5
    )

    add_common_systemd_env args

    if [[ -n "${GC2607_VCAM_MAX_RUNTIME:-}" ]]; then
        args+=(--property="RuntimeMaxSec=$GC2607_VCAM_MAX_RUNTIME")
    fi

    systemd-run "${args[@]}" "$ROOT/scripts/run-virtual-camera-feeder.sh"
    echo "Virtual camera engine started for $DEVICE."
    echo "Select '$LABEL' in the app; the real camera powers on only while the virtual device is open."
}

stop_engine() {
    if systemctl --user is-active --quiet "$UNIT"; then
        systemctl --user stop "$UNIT"
        echo "Stopped $UNIT."
    else
        echo "$UNIT is not active."
    fi
}

status() {
    local found active state caps users

    active="$(systemctl --user is-active "$UNIT" 2>/dev/null || true)"
    state="$(systemctl --user show "$UNIT" --property=SubState --value 2>/dev/null || true)"

    if found="$(find_labelled_device)"; then
        echo "Virtual camera: $found ($LABEL)"
        echo "Device name: $(video_name "$found")"
        caps="$(v4l2-ctl -D -d "$found" 2>/dev/null | sed -n '/Device Caps/,$p' | rg 'Video (Capture|Output)' | paste -sd ', ' - || true)"
        if [[ -n "$caps" ]]; then
            echo "Device caps: $caps"
        fi
        users="$(fuser "$found" 2>/dev/null | sed 's/^ *//;s/ *$//' || true)"
        if [[ -n "$users" ]]; then
            echo "Device users: $users"
        fi
    else
        echo "Virtual camera: not prepared"
    fi

    echo "Engine unit: $UNIT"
    echo "Engine state: ${active:-unknown}${state:+ ($state)}"

    if [[ -e "$RAW_DEVICE" ]] && fuser -s "$RAW_DEVICE" 2>/dev/null; then
        echo
        echo "$RAW_DEVICE users:"
        fuser -v "$RAW_DEVICE" || true
    fi
}

logs() {
    journalctl \
        --user-unit "$UNIT" \
        -n "${GC2607_VCAM_LOG_LINES:-160}" \
        --no-pager
}

run_foreground() {
    ensure_loopback
    register_pipewire_source || true
    release_raw_camera || true
    export GC2607_VCAM_DEVICE="$DEVICE"
    exec "$ROOT/scripts/run-virtual-camera-feeder.sh"
}

unload_loopback() {
    stop_engine
    sudo modprobe -r v4l2loopback
    echo "Unloaded v4l2loopback."
}

case "${1:-}" in
    prepare)
        ensure_loopback
        register_pipewire_source
        echo "Virtual camera prepared: $DEVICE ($LABEL)"
        ;;
    register)
        register_pipewire_source
        ;;
    start)
        start_engine
        ;;
    stop)
        stop_engine
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    run)
        run_foreground
        ;;
    unload)
        unload_loopback
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo "Unknown command: $1" >&2
        usage >&2
        exit 2
        ;;
esac
