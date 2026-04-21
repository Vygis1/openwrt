#!/bin/sh
# flash-openwrt-from-stock.sh — Initial OpenWrt installer for TP-Link Deco M4R v3
#
# Run this from an SSH session on the stock TP-Link firmware (obtained via
# the known 1.6.1 root exploit).
#
# Usage:
#   1. Transfer sysupgrade.bin and this script to the device:
#        scp -O openwrt-*-tplink_deco-m4r-v3-squashfs-sysupgrade.bin root@192.168.68.1:/tmp/
#        scp -O flash-openwrt-from-stock.sh root@192.168.68.1:/tmp/
#   2. SSH in and run:
#        sh /tmp/flash-openwrt-from-stock.sh /tmp/openwrt-*-squashfs-sysupgrade.bin
#
# After flashing: UNPLUG the power — do not software-reboot.

set -e

FW="${1:-/tmp/sysupgrade.bin}"
KERNEL_SIZE=4194304   # 4 MB = os-image partition size

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$FW" ] || die "Firmware not found: $FW"

FW_SIZE=$(wc -c < "$FW")
[ "$FW_SIZE" -gt "$KERNEL_SIZE" ] || die "File too small to be a valid sysupgrade image"

# Validate FIT magic (d0 0d fe ed)
MAGIC=$(dd if="$FW" bs=1 count=4 2>/dev/null | od -A n -t x1 | tr -d ' \n')
[ "$MAGIC" = "d00dfeed" ] || die "Not a valid FIT image (magic=$MAGIC). Use the sysupgrade.bin, not factory.bin."

echo "Firmware: $FW ($FW_SIZE bytes)"
echo "Locating flash partitions..."

# Find MTD device number by partition label from /proc/mtd
mtd_for_label() {
    grep "\"$1\"" /proc/mtd 2>/dev/null | sed 's/^mtd\([0-9]*\):.*/\1/'
}

# Strategy 1: OpenWrt sub-partitions (os-image@1 / file-system@1)
#   Present when already running OpenWrt, or on some stock kernels.
OS_N=$(mtd_for_label "os-image@1")
FS_N=$(mtd_for_label "file-system@1")

if [ -n "$OS_N" ] && [ -n "$FS_N" ]; then
    echo "  os-image@1    -> /dev/mtd${OS_N}"
    echo "  file-system@1 -> /dev/mtd${FS_N}"
    echo ""
    echo "Writing kernel (4 MB) to /dev/mtd${OS_N}..."
    dd if="$FW" of="/dev/mtd${OS_N}" bs=65536 count=64 conv=notrunc
    ROOTFS_SIZE=$(( FW_SIZE - KERNEL_SIZE ))
    echo "Writing rootfs ($ROOTFS_SIZE bytes) to /dev/mtd${FS_N}..."
    dd if="$FW" of="/dev/mtd${FS_N}" bs=65536 skip=64 conv=notrunc

# Strategy 2: Single firmware partition (typical stock TP-Link layout)
#   The firmware area (kernel + rootfs) is exposed as one MTD device.
#   sysupgrade.bin is structured as: [kernel 0-4MB][rootfs 4MB+]
#   so writing it directly to the firmware partition is correct.
else
    FW_N=$(mtd_for_label "firmware")
    if [ -n "$FW_N" ]; then
        echo "  firmware -> /dev/mtd${FW_N}"
        echo ""
        echo "Writing firmware to /dev/mtd${FW_N}..."
        dd if="$FW" of="/dev/mtd${FW_N}" bs=65536 conv=notrunc
    else
        echo ""
        echo "ERROR: Could not find a suitable MTD partition."
        echo "Contents of /proc/mtd:"
        cat /proc/mtd
        exit 1
    fi
fi

echo ""
echo "=== DONE ==="
echo "UNPLUG the power cable now — do NOT use 'reboot'."
echo "LuCI web interface after first boot: http://192.168.1.1/ (no password)"
