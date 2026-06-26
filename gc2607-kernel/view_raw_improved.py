#!/usr/bin/env python3
"""Improved Bayer to RGB converter with white balance and better demosaicing"""

import numpy as np
import sys
from pathlib import Path

def apply_white_balance(r, g, b, method='gray_world'):
    """Apply white balance correction"""
    if method == 'gray_world':
        # Gray world assumption: average of each channel should be equal
        r_mean = np.mean(r)
        g_mean = np.mean(g)
        b_mean = np.mean(b)

        # Use green as reference
        r_gain = g_mean / r_mean if r_mean > 0 else 1.0
        b_gain = g_mean / b_mean if b_mean > 0 else 1.0

        r = np.clip(r * r_gain, 0, 1023)
        b = np.clip(b * b_gain, 0, 1023)

    return r, g, b

def bayer_to_rgb_improved(bayer, width, height, brightness=1.0, white_balance=True):
    """Improved Bayer to RGB conversion with white balance"""
    # Reshape to 2D array
    img = bayer.reshape(height, width)

    # Extract R, G, B channels (GRBG pattern for BA10)
    h2, w2 = height // 2, width // 2

    g1 = img[0::2, 0::2][:h2, :w2].astype(np.float32)  # G channel (first)
    r = img[0::2, 1::2][:h2, :w2].astype(np.float32)   # R channel
    b = img[1::2, 0::2][:h2, :w2].astype(np.float32)   # B channel
    g2 = img[1::2, 1::2][:h2, :w2].astype(np.float32)  # G channel (second)

    # Average the two green channels
    g = (g1 + g2) / 2

    # Apply white balance
    if white_balance:
        r, g, b = apply_white_balance(r, g, b)

    # Stack into RGB
    rgb = np.stack([r, g, b], axis=2)

    # Apply brightness and normalize to 8-bit
    rgb = np.clip(rgb * brightness / 1023.0 * 255, 0, 255).astype(np.uint8)

    # Flip upside down
    rgb = np.flipud(rgb)

    return rgb

def convert_raw_to_png(raw_file, width=1920, height=1080, brightness=1.0, white_balance=True):
    """Convert raw Bayer file to PNG with improved processing"""

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
    print(f"Converting Bayer to RGB (brightness={brightness}, white_balance={white_balance})...")
    rgb = bayer_to_rgb_improved(data, width, height, brightness, white_balance)

    # Save as PNG
    output = Path(raw_file).with_suffix('.png')
    print(f"Saving to {output}...")

    from PIL import Image
    img = Image.fromarray(rgb)
    img.save(output)

    print(f"✅ Saved to {output}")
    print(f"   Size: {rgb.shape[1]}x{rgb.shape[0]}")

    return output

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: ./view_raw_improved.py <raw_file> [brightness] [white_balance]")
        print("  brightness: multiplier (default: 1.0)")
        print("  white_balance: on/off (default: on)")
        sys.exit(1)

    raw_file = sys.argv[1]
    brightness = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    wb = sys.argv[3].lower() not in ['off', 'no', '0', 'false'] if len(sys.argv) > 3 else True

    convert_raw_to_png(raw_file, brightness=brightness, white_balance=wb)
