#!/usr/bin/env python3
"""Calculate white balance gains from a raw Bayer capture"""

import numpy as np
import sys
from pathlib import Path

def calculate_wb_gains(raw_file, width=1920, height=1080):
    """Calculate gray world white balance gains from raw Bayer data"""

    print(f"Reading {raw_file}...")
    data = np.fromfile(raw_file, dtype=np.uint16)

    expected_size = width * height
    if len(data) < expected_size:
        print(f"Error: File too small ({len(data)} < {expected_size})")
        return None

    # Reshape to 2D array
    img = data[:expected_size].reshape(height, width)

    # Extract R, G, B channels (GRBG pattern)
    h2, w2 = height // 2, width // 2

    g1 = img[0::2, 0::2][:h2, :w2]  # G channel (first)
    r = img[0::2, 1::2][:h2, :w2]   # R channel
    b = img[1::2, 0::2][:h2, :w2]   # B channel
    g2 = img[1::2, 1::2][:h2, :w2]  # G channel (second)

    # Calculate channel averages
    r_avg = np.mean(r.astype(np.float32))
    g1_avg = np.mean(g1.astype(np.float32))
    g2_avg = np.mean(g2.astype(np.float32))
    b_avg = np.mean(b.astype(np.float32))

    g_avg = (g1_avg + g2_avg) / 2

    # Calculate gains (use green as reference)
    r_gain = g_avg / (r_avg + 1e-6)
    b_gain = g_avg / (b_avg + 1e-6)
    g_gain = 1.0

    print(f"\nChannel averages:")
    print(f"  R: {r_avg:.1f}")
    print(f"  G: {g_avg:.1f}")
    print(f"  B: {b_avg:.1f}")
    print(f"\nGray World White Balance Gains:")
    print(f"  Red:   {r_gain:.3f}")
    print(f"  Green: {g_gain:.3f}")
    print(f"  Blue:  {b_gain:.3f}")
    print(f"\nTo use these gains, run:")
    print(f"  ./create_virtual_camera_wb.sh {r_gain:.3f} {g_gain:.3f} {b_gain:.3f}")

    return (r_gain, g_gain, b_gain)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: ./calculate_wb_gains.py <raw_file>")
        print("\nThis script calculates optimal white balance gains from a raw capture.")
        print("Steps:")
        print("  1. Capture a raw frame:")
        print("     v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=wb_test.raw")
        print("  2. Calculate gains:")
        print("     ./calculate_wb_gains.py wb_test.raw")
        print("  3. Use the gains in the virtual camera script")
        sys.exit(1)

    raw_file = sys.argv[1]
    calculate_wb_gains(raw_file)
