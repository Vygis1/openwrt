#!/bin/sh
# flash-openwrt-m4r.sh — Initial OpenWrt installer for TP-Link Deco M4R v3
#
# Run this from an SSH session on the stock TP-Link firmware (obtained via
# the known 1.6.1 root exploit).  It downloads or accepts a local path to
# the OpenWrt sysupgrade image and writes it to the correct flash partitions.
#
# Usage:
#   1. Transfer sysupgrade.bin to the device first:
#        scp openwrt-*-tplink_deco-m4r-v3-squashfs-sysupgrade.bin root@192.168.68.1:/tmp/sysupgrade.bin
#   2. SSH in and run:
#        sh /tmp/flash-openwrt-m4r.sh /tmp/sysupgrade.bin
#
# After flashing: UNPLUG the power — do not software-reboot.
# On the first boot U-Boot will go through a two-step reset (crashdump detect),
# then land in OpenWrt.  LuCI is at http://192.168.1.1/ — no password.

set -e

FW="${1:-/tmp/sysupgrade.bin}"
KERNEL_SIZE=4194304   # 4 MB = os-image@1 partition

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$FW" ] || die "Firmware not found: $FW"

FW_SIZE=$(wc -c < "$FW")
[ "$FW_SIZE" -gt "$KERNEL_SIZE" ] || die "File too small to be a valid sysupgrade image"

# Validate FIT magic (d0 0d fe ed)
MAGIC=$(dd if="$FW" bs=1 count=4 2>/dev/null | od -A n -t x1 | tr -d ' \n')
[ "$MAGIC" = "d00dfeed" ] || die "Not a valid FIT image (magic=$MAGIC). Use the sysupgrade.bin, not factory.bin."

echo "Firmware: $FW ($FW_SIZE bytes)"
echo "Locating flash partitions..."

# Find MTD device number by label from /proc/mtd
mtd_for_label() {
    local label="$1"
    grep "\"$label\"" /proc/mtd 2>/dev/null | sed 's/^mtd\([0-9]*\):.*/\1/'
}

OS_N=$(mtd_for_label "os-image@1")
FS_N=$(mtd_for_label "file-system@1")

[ -n "$OS_N" ] || die "Could not find 'os-image@1' partition in /proc/mtd"
[ -n "$FS_N" ] || die "Could not find 'file-system@1' partition in /proc/mtd"

echo "  os-image@1   -> /dev/mtd${OS_N}"
echo "  file-system@1 -> /dev/mtd${FS_N}"
echo ""
echo "Writing kernel (first 4 MB) to /dev/mtd${OS_N}..."
dd if="$FW" of="/dev/mtd${OS_N}" bs=65536 count=64 conv=notrunc

ROOTFS_SIZE=$(( FW_SIZE - KERNEL_SIZE ))
echo "Writing rootfs ($ROOTFS_SIZE bytes) to /dev/mtd${FS_N}..."
dd if="$FW" of="/dev/mtd${FS_N}" bs=65536 skip=64 conv=notrunc

echo ""
echo "=== DONE ==="
echo "UNPLUG the power cable now — do NOT use 'reboot'."
echo "On first boot the device will reset once (normal), then boot OpenWrt."
echo "LuCI web interface: http://192.168.1.1/"
