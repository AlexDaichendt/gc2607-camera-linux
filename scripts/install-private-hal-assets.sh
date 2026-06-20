#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 HAL_REPO PRIVATE_ASSET_DIR" >&2
    exit 2
fi

HAL_REPO="$1"
ASSET_DIR="$2"

if [[ ! -d "$HAL_REPO/config/linux/ipu6epmtl" ]]; then
    echo "Not an expected IPU6 HAL repo: $HAL_REPO" >&2
    exit 1
fi

required=(
    "gc2607_gc2607_MTL.aiqb"
    "graph_settings_gc2607_gc2607_MTL.xml"
)

for file in "${required[@]}"; do
    if [[ ! -f "$ASSET_DIR/$file" ]]; then
        echo "Missing private asset: $ASSET_DIR/$file" >&2
        exit 1
    fi
done

install -D -m 0644 \
    "$ASSET_DIR/gc2607_gc2607_MTL.aiqb" \
    "$HAL_REPO/config/linux/ipu6epmtl/gc2607_gc2607_MTL.aiqb"

install -D -m 0644 \
    "$ASSET_DIR/graph_settings_gc2607_gc2607_MTL.xml" \
    "$HAL_REPO/config/linux/ipu6epmtl/gcss/graph_settings_gc2607_gc2607_MTL.xml"

if [[ -f "$ASSET_DIR/graph_descriptor.xml" ]]; then
    install -D -m 0644 \
        "$ASSET_DIR/graph_descriptor.xml" \
        "$HAL_REPO/config/linux/ipu6epmtl/gcss/graph_descriptor.xml"
fi

echo "Installed GC2607 private HAL assets into $HAL_REPO"
sha256sum \
    "$HAL_REPO/config/linux/ipu6epmtl/gc2607_gc2607_MTL.aiqb" \
    "$HAL_REPO/config/linux/ipu6epmtl/gcss/graph_settings_gc2607_gc2607_MTL.xml" \
    "$HAL_REPO/config/linux/ipu6epmtl/gcss/graph_descriptor.xml" 2>/dev/null || true
