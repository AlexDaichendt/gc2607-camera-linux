#!/bin/bash
# Setup permissions for camera operations without sudo password

set -e

echo "=== Setting Up Permissions ==="
echo ""

# Add user to video group
echo "1. Adding $USER to 'video' group..."
sudo usermod -aG video $USER

# Create sudoers file for passwordless camera operations
SUDOERS_FILE="/etc/sudoers.d/gc2607-camera"

echo "2. Creating sudoers configuration..."
sudo tee "$SUDOERS_FILE" > /dev/null <<EOF
# Allow $USER to manage camera driver without password
$USER ALL=(ALL) NOPASSWD: /usr/bin/insmod /home/abbood/dev/camera-driver-dev/gc2607-v4l2-driver/gc2607.ko
$USER ALL=(ALL) NOPASSWD: /usr/bin/rmmod gc2607
$USER ALL=(ALL) NOPASSWD: /usr/bin/modprobe videodev
$USER ALL=(ALL) NOPASSWD: /usr/bin/modprobe v4l2-async
$USER ALL=(ALL) NOPASSWD: /usr/bin/modprobe ipu_bridge
$USER ALL=(ALL) NOPASSWD: /usr/bin/modprobe intel-ipu6
$USER ALL=(ALL) NOPASSWD: /usr/bin/modprobe intel-ipu6-isys
$USER ALL=(ALL) NOPASSWD: /usr/bin/modprobe -r intel-ipu6-isys
$USER ALL=(ALL) NOPASSWD: /usr/bin/modprobe -r intel-ipu6
$USER ALL=(ALL) NOPASSWD: /usr/bin/modprobe v4l2loopback *
$USER ALL=(ALL) NOPASSWD: /usr/bin/dmesg
EOF

sudo chmod 0440 "$SUDOERS_FILE"

echo ""
echo "✅ Permissions configured!"
echo ""
echo "⚠️  IMPORTANT: You need to log out and log back in for group changes to take effect."
echo ""
echo "After logging back in:"
echo "  - You'll have access to /dev/video* devices"
echo "  - sudo commands for camera driver won't require password"
echo ""
echo "Test with: groups (should show 'video' in the list)"
