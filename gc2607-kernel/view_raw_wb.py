#!/usr/bin/env python3
"""Convert raw Bayer GRBG10 image to viewable PNG with white balance and brightness boost"""

import numpy as np
import sys
from pathlib import Path

def apply_white_balance(rgb, method='gray_world'):
    """Apply white balance correction to RGB image

    Args:
        rgb: numpy array of shape (H, W, 3) with R, G, B channels
        method: 'gray_world' or 'max_white'

    Returns:
        White balanced RGB image
    """
    rgb_float = rgb.astype(np.float32)

    if method == 'gray_world':
        # Gray world assumption: average of each channel should be equal
        r_avg = np.mean(rgb_float[:, :, 0])
        g_avg = np.mean(rgb_float[:, :, 1])
        b_avg = np.mean(rgb_float[:, :, 2])

        # Use green as reference (since it has highest SNR)
        r_gain = g_avg / (r_avg + 1e-6)
        b_gain = g_avg / (b_avg + 1e-6)

        print(f"White balance gains: R={r_gain:.3f}, G=1.000, B={b_gain:.3f}")

        rgb_float[:, :, 0] *= r_gain
        rgb_float[:, :, 2] *= b_gain

    elif method == 'max_white':
        # Max white: scale each channel to use full range
        r_max = np.max(rgb_float[:, :, 0])
        g_max = np.max(rgb_float[:, :, 1])
        b_max = np.max(rgb_float[:, :, 2])

        gray_max = (r_max + g_max + b_max) / 3

        r_gain = gray_max / (r_max + 1e-6)
        g_gain = gray_max / (g_max + 1e-6)
        b_gain = gray_max / (b_max + 1e-6)

        print(f"White balance gains: R={r_gain:.3f}, G={g_gain:.3f}, B={b_gain:.3f}")

        rgb_float[:, :, 0] *= r_gain
        rgb_float[:, :, 1] *= g_gain
        rgb_float[:, :, 2] *= b_gain

    return rgb_float

def bayer_to_rgb_wb(bayer, width, height, brightness=3.0, wb_method='gray_world'):
    """Bayer to RGB conversion with white balance and brightness adjustment"""
    # Reshape to 2D array
    img = bayer.reshape(height, width)

    # Extract R, G, B channels (GRBG pattern)
    h2, w2 = height // 2, width // 2

    g1 = img[0::2, 0::2][:h2, :w2]  # G channel (first)
    r = img[0::2, 1::2][:h2, :w2]   # R channel
    b = img[1::2, 0::2][:h2, :w2]   # B channel
    g2 = img[1::2, 1::2][:h2, :w2]  # G channel (second)

    # Average the two green channels
    g = (g1.astype(np.float32) + g2.astype(np.float32)) / 2

    # Stack into RGB
    rgb = np.stack([r.astype(np.float32), g, b.astype(np.float32)], axis=2)

    # Apply white balance BEFORE brightness and normalization
    rgb = apply_white_balance(rgb, method=wb_method)

    # Apply brightness boost and normalize to 8-bit
    rgb = np.clip(rgb * brightness / 1023.0 * 255, 0, 255).astype(np.uint8)

    # Flip upside down
    rgb = np.flipud(rgb)

    return rgb

def convert_raw_to_png(raw_file, width=1920, height=1080, brightness=3.0, wb_method='gray_world'):
    """Convert raw Bayer file to PNG with white balance"""

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

    # Convert to RGB with white balance
    print(f"Converting Bayer to RGB (brightness={brightness}, wb={wb_method})...")
    rgb = bayer_to_rgb_wb(data, width, height, brightness, wb_method)

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
        print("PIL not available")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: ./view_raw_wb.py <raw_file> [brightness=3.0] [wb_method=gray_world]")
        print("Example: ./view_raw_wb.py test.raw 5.0 gray_world")
        print("White balance methods: gray_world, max_white")
        sys.exit(1)

    raw_file = sys.argv[1]
    brightness = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
    wb_method = sys.argv[3] if len(sys.argv) > 3 else 'gray_world'

    convert_raw_to_png(raw_file, brightness=brightness, wb_method=wb_method)
