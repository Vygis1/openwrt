# OpenWrt on TP-Link Deco M4R v3

This directory contains installation tools and documentation for running OpenWrt on the **TP-Link Deco M4R v3**.

Pre-built firmware images are available in [Releases](../../releases).

---

## Hardware

| Component | Details |
|-----------|---------|
| SoC | Qualcomm IPQ4019 (quad-core ARM Cortex-A7 @ 717 MHz) |
| RAM | 256 MB DDR3L |
| Flash | 32 MB SPI NOR |
| WiFi 2.4 GHz | IPQ4019 integrated (2×2, 802.11n) |
| WiFi 5 GHz | IPQ4019 integrated (2×2, 802.11ac) |
| Ethernet | 2× (1× LAN, 1× WAN via IPQ4019 internal ESS switch) |
| LEDs | Red / Green / Blue (GPIO) |
| Reset button | GPIO 18 (hold 10 s to reset) |
| UART | 3.3 V, 115200 8N1 |

### Flash layout

| mtd | Label | Offset | Size | Notes |
|-----|-------|--------|------|-------|
| mtd0 | 0:SBL1 | 0x000000 | 192 KB | Secondary boot loader |
| mtd1 | 0:BOOTCONFIG | 0x030000 | 64 KB | |
| mtd2 | 0:MIBIB | 0x040000 | 64 KB | |
| mtd3 | 0:BOOTCONFIG1 | 0x050000 | 64 KB | |
| mtd4 | 0:QSEE | 0x060000 | 384 KB | TrustZone |
| mtd5 | 0:CDT | 0x0c0000 | 64 KB | |
| mtd6 | 0:DDRPARAMS | 0x0d0000 | 64 KB | |
| mtd7 | 0:APPSBLENV | 0x0e0000 | 64 KB | U-Boot environment |
| mtd8 | 0:APPSBL | 0x0f0000 | 512 KB | U-Boot |
| mtd9 | 0:ART | 0x170000 | 64 KB | WiFi pre-calibration |
| mtd10 | OPAQUE | 0x180000 | 768 KB | MAC / serial / region data |
| mtd11 | 0:HLOS | 0x240000 | 3.1 MB | Stock kernel |
| mtd12 | 0:rootfs | 0x560000 | 10.2 MB | Stock rootfs |
| mtd13 | 0:APPSBL_1 | 0xfa0000 | 512 KB | Backup U-Boot |
| mtd14 | firmware | 0x1020000 | ~16 MB | **OpenWrt lives here** |

---

## Installing OpenWrt

### Method 1 — From stock firmware via SSH (easiest)

This method works if your Deco M4R v3 is running stock firmware **1.6.1** (the version with a known SSH exploit).
No UART or disassembly required.

**Requirements:**
- Stock firmware version 1.6.1
- SSH access to the router (root shell via the exploit)
- The files from this release: `flash-openwrt-from-stock.sh` and `openwrt-...-squashfs-sysupgrade.bin`

**Steps:**

1. Gain SSH root access using the exploit at [naf419/tplink_deco_exploits](https://github.com/naf419/tplink_deco_exploits/tree/main/userspace_fw_upgrade).

2. Copy the files to the router:
   ```sh
   scp -O flash-openwrt-from-stock.sh root@192.168.68.1:/tmp/
   scp -O openwrt-ipq40xx-generic-tplink_deco-m4r-v3-squashfs-sysupgrade.bin root@192.168.68.1:/tmp/
   ```

3. SSH in and run the flash script:
   ```sh
   ssh root@192.168.68.1
   chmod +x /tmp/flash-openwrt-from-stock.sh
   /tmp/flash-openwrt-from-stock.sh /tmp/openwrt-ipq40xx-generic-tplink_deco-m4r-v3-squashfs-sysupgrade.bin
   ```

4. The script will validate, flash, and print `Done. You can now reboot.`. Unplug and replug power.

5. OpenWrt boots. LuCI web interface is at **http://192.168.1.1**. No password is set by default — set one immediately.

---

### Method 2 — Via U-Boot HTTP recovery (UART required)

Use this if you bricked the device or can't use Method 1.

**Requirements:**
- UART connection (3.3 V, 115200 8N1)
- A PC on the same LAN as the router
- `openwrt-...-squashfs-factory.bin`

**Steps:**

1. Connect UART. Power on while holding reset to enter U-Boot shell (or interrupt autoboot by pressing a key when prompted).

2. In U-Boot, start the built-in HTTP server:
   ```
   httpd
   ```

3. In a browser, navigate to **http://192.168.0.1** and upload `factory.bin`.
   The page will show an error ("NM format mismatch") — **this is expected**. The file is still loaded into RAM.

4. The firmware is now at RAM address `0x82000000`. Flash it:
   ```
   sf probe
   sf erase 0x1020000 0x1000000
   sf write 0x82000000 0x1020000 0x860000
   ```

5. Boot directly to verify before resetting U-Boot env:
   ```
   sf read 0x84000000 0x1020000 0x400000
   bootm 0x84000000
   ```

6. If OpenWrt boots successfully, the U-Boot environment is automatically configured on first boot via the uci-defaults script. Hard power-cycle to confirm auto-boot works.

> **Note:** The custom `bootcmd` (`sf probe; sf read 0x84000000 0x1020000 0x400000; bootm 0x84000000`) and `verify=no` are written to APPSBLENV on first boot. They persist across reboots.

---

## Upgrading OpenWrt

**First upgrade** (from stock or an earlier build without DSA metadata):

```sh
sysupgrade -F -n /tmp/openwrt-...-squashfs-sysupgrade.bin
```

The `-F` flag is required for the first upgrade because our image carries `compat_version: 1.1` (DSA network switch migration marker) while the previous environment has `1.0`. Subsequent OpenWrt-to-OpenWrt upgrades do not need `-F`.

**Subsequent upgrades** (OpenWrt → OpenWrt):

```sh
sysupgrade -n /tmp/openwrt-...-squashfs-sysupgrade.bin
```

Use `-n` to discard settings (recommended for major version jumps). Omit `-n` to keep settings.

---

## Building from source

```sh
git clone https://github.com/openwrt/openwrt.git
cd openwrt
git remote add deco https://github.com/Vygis1/openwrt.git
git fetch deco
git checkout -b tplink-deco-m4r-v3 deco/tplink-deco-m4r-v3

./scripts/feeds update -a
./scripts/feeds install -a

make menuconfig
# Select: Target: ipq40xx → Subtarget: generic → Target Profile: TP-Link Deco M4R v3

make -j$(nproc)
```

Output images will be in `bin/targets/ipq40xx/generic/`.

---

## Known issues

- **MAC address warning on boot**: `Failed to find NVMEM device` may appear in dmesg. The device still boots and operates correctly; the MAC is read from the OPAQUE partition. This is a cosmetic issue under investigation.
- **WiFi LED**: Currently maps to the blue LED (power/boot indicator). Fine-grained per-radio LED mapping is not yet implemented.

---

## Credits

Port developed by [Vyga Valantiejus](https://github.com/Vygis1).
Based on OpenWrt's ipq40xx target.
