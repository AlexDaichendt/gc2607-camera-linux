#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UNIT_NAME="${GC2607_VCAM_UNIT_NAME:-gc2607-virtual-camera}"
UNIT="${UNIT_NAME}.service"
WATCH_UNIT_NAME="${UNIT_NAME}-watch"
WATCH_UNIT="${WATCH_UNIT_NAME}.service"
STANDBY_UNIT_NAME="${UNIT_NAME}-standby"
STANDBY_UNIT="${STANDBY_UNIT_NAME}.service"
VIDEO_NR="${GC2607_VCAM_VIDEO_NR:-60}"
DEVICE="${GC2607_VCAM_DEVICE:-/dev/video${VIDEO_NR}}"
LABEL="${GC2607_VCAM_LABEL:-GC2607 Virtual Camera}"
EXCLUSIVE_CAPS="${GC2607_VCAM_EXCLUSIVE_CAPS:-1}"
RAW_DEVICE="${GC2607_RAW_DEVICE:-/dev/video0}"
WATCH_IDLE_SECONDS="${GC2607_VCAM_IDLE_SECONDS:-8}"
WATCH_POLL_SECONDS="${GC2607_VCAM_POLL_SECONDS:-1}"

if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

usage() {
    cat <<EOF
Usage: $(basename "$0") COMMAND

Commands:
  prepare   Create/refresh the virtual webcam without starting the real camera
  register  Refresh PipeWire visibility for the virtual device, no real camera
  start     Arm the on-demand watcher; real camera starts only while used
  force-start
            Start the real GC2607 -> v4l2loopback feeder immediately
  stop      Stop the watcher, standby stream, and feeder
  status    Show feeder and virtual device state
  logs      Show recent watcher/feeder logs
  run       Run the feeder in the foreground
  unload    Stop all virtual-camera services and unload v4l2loopback

Environment:
  GC2607_VCAM_VIDEO_NR       video node number, default: 60
  GC2607_VCAM_LABEL          loopback card label, default: GC2607 Virtual Camera
  GC2607_VCAM_WIDTH          output width, default: 1280
  GC2607_VCAM_HEIGHT         output height, default: 720
  GC2607_VCAM_FRAMERATE      output framerate, default: 30/1
  GC2607_VCAM_FORMAT         output format, default: YUY2
  GC2607_VCAM_IDLE_SECONDS   seconds with no users before stopping real camera, default: 8
  GC2607_VCAM_MAX_RUNTIME    optional systemd RuntimeMaxSec, for example 90min
  GC2607_RAW_DEVICE          raw IPU6 capture node to check, default: /dev/video0
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
        max_buffers=2

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

device_has_capture_caps() {
    v4l2-ctl -D -d "$DEVICE" 2>/dev/null | rg -q "Video Capture"
}

add_common_systemd_env() {
    local -n out="$1"
    local var

    out+=(
        --setenv="GC2607_VCAM_DEVICE=$DEVICE"
        --setenv="GC2607_VCAM_VIDEO_NR=$VIDEO_NR"
        --setenv="GC2607_VCAM_LABEL=$LABEL"
        --setenv="GC2607_RAW_DEVICE=$RAW_DEVICE"
        --setenv="GC2607_VCAM_IDLE_SECONDS=$WATCH_IDLE_SECONDS"
        --setenv="GC2607_VCAM_POLL_SECONDS=$WATCH_POLL_SECONDS"
    )

    for var in \
        GC2607_PREFIX \
        GC2607_FLIP_METHOD \
        GC2607_VCAM_SOURCE_WIDTH \
        GC2607_VCAM_SOURCE_HEIGHT \
        GC2607_VCAM_WIDTH \
        GC2607_VCAM_HEIGHT \
        GC2607_VCAM_FRAMERATE \
        GC2607_VCAM_FORMAT \
        GC2607_VCAM_MAX_RUNTIME; do
        if [[ -n "${!var+x}" ]]; then
            out+=(--setenv="$var=${!var}")
        fi
    done
}

unit_main_pid() {
    local unit="$1"
    local pid

    pid="$(systemctl --user show "$unit" --property=MainPID --value 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$pid"
    else
        printf '0\n'
    fi
}

device_pids() {
    fuser "$DEVICE" 2>/dev/null | tr ' ' '\n' | rg '^[0-9]+$' || true
}

consumer_pids() {
    local feeder_pid standby_pid pid

    feeder_pid="$(unit_main_pid "$UNIT")"
    standby_pid="$(unit_main_pid "$STANDBY_UNIT")"

    while read -r pid; do
        [[ -n "$pid" ]] || continue
        [[ "$pid" == "$feeder_pid" ]] && continue
        [[ "$pid" == "$standby_pid" ]] && continue
        printf '%s\n' "$pid"
    done < <(device_pids)
}

has_consumers() {
    [[ -n "$(consumer_pids | head -n 1)" ]]
}

start_standby() {
    local args=()
    local producer=()

    ensure_loopback

    if systemctl --user is-active --quiet "$UNIT"; then
        return 0
    fi

    if systemctl --user is-active --quiet "$STANDBY_UNIT"; then
        return 0
    fi

    args=(
        --user
        --unit="$STANDBY_UNIT_NAME"
        --description="GC2607 virtual camera standby stream"
        --collect
        --property=Restart=on-failure
        --property=RestartSec=2
    )

    producer=(
        /usr/bin/gst-launch-1.0 -q -e
        videotestsrc is-live=true pattern=black
        "!"
        "video/x-raw,format=${GC2607_VCAM_FORMAT:-YUY2},width=${GC2607_VCAM_WIDTH:-1280},height=${GC2607_VCAM_HEIGHT:-720},framerate=${GC2607_VCAM_FRAMERATE:-30/1}"
        "!"
        v4l2sink "device=$DEVICE" sync=false
    )

    systemd-run "${args[@]}" "${producer[@]}" >/dev/null

    for _ in {1..20}; do
        if device_has_capture_caps; then
            return 0
        fi
        sleep 0.1
    done

    echo "Started standby stream, but $DEVICE has not switched to capture mode yet." >&2
}

stop_standby() {
    if systemctl --user is-active --quiet "$STANDBY_UNIT"; then
        systemctl --user stop "$STANDBY_UNIT"
    fi
}

register_pipewire_source() {
    local registered=0

    ensure_loopback

    if ! command -v systemd-run >/dev/null 2>&1; then
        echo "systemd-run is missing; cannot refresh PipeWire virtual-camera visibility." >&2
        return 1
    fi

    start_standby

    if pipewire_has_virtual_source; then
        echo "PipeWire source registered for $DEVICE."
        return 0
    fi

    sleep 1
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

start_feeder_now() {
    local args=()

    ensure_loopback
    if ! release_raw_camera; then
        return 1
    fi

    if systemctl --user is-active --quiet "$UNIT"; then
        echo "$UNIT is already active."
        echo "Virtual camera: $DEVICE"
        return 0
    fi

    stop_standby

    args=(
        --user
        --unit="$UNIT_NAME"
        --description="GC2607 virtual camera feeder"
        --collect
        --same-dir
        --property=Restart=no
    )

    add_common_systemd_env args

    if [[ -n "${GC2607_VCAM_MAX_RUNTIME:-}" ]]; then
        args+=(--property="RuntimeMaxSec=$GC2607_VCAM_MAX_RUNTIME")
    fi

    systemd-run "${args[@]}" "$ROOT/scripts/run-virtual-camera-feeder.sh"
    echo "Virtual camera feeder started for $DEVICE."
}

stop_feeder() {
    if systemctl --user is-active --quiet "$UNIT"; then
        systemctl --user stop "$UNIT"
        echo "Stopped $UNIT."
    else
        echo "$UNIT is not active."
    fi
}

start_watcher() {
    local args=()

    ensure_loopback

    if systemctl --user is-active --quiet "$WATCH_UNIT"; then
        echo "$WATCH_UNIT is already active."
        echo "Virtual camera: $DEVICE"
        return 0
    fi

    register_pipewire_source

    args=(
        --user
        --unit="$WATCH_UNIT_NAME"
        --description="GC2607 on-demand virtual camera watcher"
        --collect
        --same-dir
        --property=Restart=on-failure
        --property=RestartSec=5
    )

    add_common_systemd_env args

    systemd-run "${args[@]}" "$0" watch-foreground
    echo "On-demand virtual camera armed for $DEVICE."
    echo "Select '$LABEL' in the app; the real camera starts only while the virtual device is open."
}

stop_watcher() {
    if systemctl --user is-active --quiet "$WATCH_UNIT"; then
        systemctl --user stop "$WATCH_UNIT"
        echo "Stopped $WATCH_UNIT."
    else
        echo "$WATCH_UNIT is not active."
    fi
}

stop_all() {
    stop_watcher
    stop_feeder
    stop_standby
}

watch_foreground() {
    local idle_since=0
    local now consumers

    trap 'stop_feeder >/dev/null 2>&1 || true; stop_standby >/dev/null 2>&1 || true; exit 0' INT TERM

    ensure_loopback
    register_pipewire_source
    echo "Watching $DEVICE; idle timeout is ${WATCH_IDLE_SECONDS}s."

    while true; do
        consumers="$(consumer_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

        if systemctl --user is-active --quiet "$UNIT"; then
            if [[ -n "$consumers" ]]; then
                idle_since=0
            else
                now="$(date +%s)"
                if [[ "$idle_since" == 0 ]]; then
                    idle_since="$now"
                elif (( now - idle_since >= WATCH_IDLE_SECONDS )); then
                    echo "No virtual-camera consumers for ${WATCH_IDLE_SECONDS}s; stopping real camera."
                    stop_feeder >/dev/null 2>&1 || true
                    start_standby || true
                    idle_since=0
                fi
            fi
        else
            idle_since=0
            start_standby || true
            if [[ -n "$consumers" ]]; then
                echo "Virtual-camera consumer detected: $consumers"
                if start_feeder_now; then
                    echo "Real camera feeder is active."
                else
                    echo "Could not start real camera feeder; keeping standby stream active." >&2
                    start_standby || true
                    sleep 3
                fi
            fi
        fi

        sleep "$WATCH_POLL_SECONDS"
    done
}

status() {
    local found active state watch_active watch_state standby_active standby_state caps users

    active="$(systemctl --user is-active "$UNIT" 2>/dev/null || true)"
    state="$(systemctl --user show "$UNIT" --property=SubState --value 2>/dev/null || true)"
    watch_active="$(systemctl --user is-active "$WATCH_UNIT" 2>/dev/null || true)"
    watch_state="$(systemctl --user show "$WATCH_UNIT" --property=SubState --value 2>/dev/null || true)"
    standby_active="$(systemctl --user is-active "$STANDBY_UNIT" 2>/dev/null || true)"
    standby_state="$(systemctl --user show "$STANDBY_UNIT" --property=SubState --value 2>/dev/null || true)"

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

    echo "Watcher unit: $WATCH_UNIT"
    echo "Watcher state: ${watch_active:-unknown}${watch_state:+ ($watch_state)}"
    echo "Standby unit: $STANDBY_UNIT"
    echo "Standby state: ${standby_active:-unknown}${standby_state:+ ($standby_state)}"
    echo "Feeder unit: $UNIT"
    echo "Feeder state: ${active:-unknown}${state:+ ($state)}"

    if [[ -e "$RAW_DEVICE" ]] && fuser -s "$RAW_DEVICE" 2>/dev/null; then
        echo
        echo "$RAW_DEVICE users:"
        fuser -v "$RAW_DEVICE" || true
    fi
}

logs() {
    journalctl \
        --user-unit "$WATCH_UNIT" \
        --user-unit "$UNIT" \
        --user-unit "$STANDBY_UNIT" \
        -n "${GC2607_VCAM_LOG_LINES:-160}" \
        --no-pager
}

run_foreground() {
    ensure_loopback
    export GC2607_VCAM_DEVICE="$DEVICE"
    exec "$ROOT/scripts/run-virtual-camera-feeder.sh"
}

unload_loopback() {
    stop_all
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
        start_watcher
        ;;
    force-start)
        start_feeder_now
        ;;
    stop)
        stop_all
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
    watch-foreground)
        watch_foreground
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
