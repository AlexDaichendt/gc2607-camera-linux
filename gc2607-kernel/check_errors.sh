#!/bin/bash
# Check kernel logs for errors

echo "=== Recent kernel messages ==="
echo ""
sudo dmesg -T | tail -50
