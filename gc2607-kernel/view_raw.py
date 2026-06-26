#!/usr/bin/env python3
"""Convert raw Bayer GRBG10 image to viewable PNG"""

import numpy as np
import sys
from pathlib import Path

def bayer_to_rgb_simple(bayer, width, height):
    """Simple Bayer to RGB conversion (2x2 downsampling)"""
    # Reshape to 2D array
    img = bayer.reshape(height, width)

    # Extract R, G, B channels (simple 2x2 demosaicing)
    # GRBG pattern:
    # G R G R
    # B G B G
    h2, w2 = height // 2, width // 2

    r = img[0::2, 1::2][:h2, :w2]  # R channel
    g1 = img[0::2, 0::2][:h2, :w2]  # G channel (first)
    g2 = img[1::2, 1::2][:h2, :w2]  # G channel (second)
    b = img[1::2, 0::2][:h2, :w2]  # B channel

    g = (g1.astype(np.float32) + g2.astype(np.float32)) / 2

    # Stack into RGB
    rgb = np.stack([r, g, b], axis=2)

    # Normalize to 8-bit
    rgb = (rgb / 1023.0 * 255).astype(np.uint8)

    return rgb

def convert_raw_to_png(raw_file, width=1920, height=1080, bits=10):
    """Convert raw Bayer file to PNG"""

    # Read raw file
    print(f"Reading {raw_file}...")
    data = np.fromfile(raw_file, dtype=np.uint16)

    expected_size = width * height
    actual_size = len(data)

    print(f"Expected pixels: {expected_size}")
    print(f"Actual pixels: {actual_size}")

    if actual_size < expected_size:
        print(f"Warning: File too small, padding with zeros")
        data = np.pad(data, (0, expected_size - actual_size))
    elif actual_size > expected_size:
        print(f"Warning: File too large, truncating")
        data = data[:expected_size]

    # Convert to RGB
    print("Converting Bayer to RGB...")
    rgb = bayer_to_rgb_simple(data, width, height)

    # Save as PNG
    output = Path(raw_file).with_suffix('.png')
    print(f"Saving to {output}...")

    try:
        from PIL import Image
        img = Image.fromarray(rgb)
        img.save(output)
        print(f"✅ Saved to {output}")
        print(f"   Size: {rgb.shape[1]}x{rgb.shape[0]}")
        return True
    except ImportError:
        print("PIL not available, saving as numpy array")
        np.save(output.with_suffix('.npy'), rgb)
        print(f"✅ Saved numpy array to {output.with_suffix('.npy')}")
        print("   Install PIL/Pillow to save as PNG: pip install pillow")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: ./view_raw.py <raw_file> [width] [height]")
        print("Example: ./view_raw.py test.raw 1920 1080")
        sys.exit(1)

    raw_file = sys.argv[1]
    width = int(sys.argv[2]) if len(sys.argv) > 2 else 1920
    height = int(sys.argv[3]) if len(sys.argv) > 3 else 1080

    convert_raw_to_png(raw_file, width, height)
