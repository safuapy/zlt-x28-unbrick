# ZLT-X28 (MT6890 NAND) Recovery Guide

## Background

The ZLT-X28 is a 5G CPE router based on the MediaTek MT6890 (T750 platform) with a Quectel RG500L-EU modem module. It uses **NAND flash** (not eMMC/UFS) with a **PMT (Partition Management Table)** instead of GPT.

If your router is bricked, locked out, or has a corrupted partition, you can recover it using `mtkclient` with the patches and files in this package.

### When to use this guide

- Router web UI is inaccessible (locked out, services disabled)
- Router doesn't boot properly after a bad firmware update
- You need to flash a new rootfs, boot, or modem partition
- `mtkclient` fails with "No da_loader" or crashes on MT6880/MT6890
- You get `AttributeError: 'bool' object has no attribute 'decode'` or `AttributeError: 'list' object has no attribute 'name'`

### Why upstream mtkclient doesn't work

The upstream `bkerler/mtkclient` has 4 issues with this device:

1. **NAND vs GPT**: Upstream assumes GPT partition tables. The ZLT-X28 uses NAND with PMT. All partition operations hit the wrong code path.
2. **DA batch limit**: The DA firmware caps reads at 26MB per session. Large partitions (modem: 33MB, rootfs: 64MB) fail silently.
3. **Thumb-mode DA binary**: The DA2 binary uses ARM Thumb instructions (16/32-bit mixed). The patcher only handles ARM32, causing all security patches to fail with `assert` crashes.
4. **Off-by-one flash size**: Full-flash reads are rejected by the DA's boundary check.

---

## Prerequisites

### Hardware
- ZLT-X28 router (any firmware version)
- USB Type-C cable (data capable, not charge-only)
- Computer running Linux or macOS (Windows works but this guide uses Linux/macOS paths)

### Software
- Python 3.8+
- `git`
- `pip3`
- USB drivers for MediaTek Preloader (on Linux, `modemmanager` may interfere — see troubleshooting)

### This package contains
```
zlt-x28-unbrick/
├── RECOVERY_GUIDE.md              ← you are here
├── apply_patch.sh                 ← automated patch script
├── zlt_x28_nand_support.patch     ← the patch itself
├── MT6890_ZLT_X28_scatter.xml     ← partition layout for ZLT-X28
├── MT6890_openwrt_scatter.xml     ← alternate partition layout (OpenWrt)
├── da_loader/
│   ├── DA_BR.bin                  ← custom Download Agent (from Quectel firmware)
│   ├── DA_BR_unsign.bin           ← custom Download Agent (unsigned)
│   ├── flash.xml                  ← DA flash configuration
│   └── flash.xsd                  ← DA flash schema
└── firmware/
    ├── boot-stock.img             ← STOCK boot image (33MB, full NAND partition)
    ├── ubi-rootfs-stock.ubi       ← STOCK rootfs in UBI format (64MB, full partition)
    ├── root_ro-stock.sig          ← root_ro signature file
    ├── boot_a.bin                 ← Backup dump of boot_a partition (33MB)
    ├── boot_b.bin                 ← Backup dump of boot_b partition (33MB)
    └── rootfs_a.bin              ← Backup dump of rootfs_a partition (64MB)
```

### About the firmware files

**IMPORTANT**: The `boot-stock.img` and `ubi-rootfs-stock.ubi` files are **full NAND partition-sized images** — they are padded to the exact partition size (33MB for boot, 64MB for rootfs). These are NOT the same as the raw Quectel OpenWrt images (9MB `boot.img`, 24MB `root.squashfs`) which are smaller and won't work when flashed directly to NAND partitions.

- **`boot-stock.img`** (33MB): Full boot partition image with NAND padding. Contains the Android boot image (kernel + ramdisk) padded to partition size.
- **`ubi-rootfs-stock.ubi`** (64MB): UBI container with squashfs rootfs inside. The UBI layer is required for NAND wear leveling. Flashing raw squashfs without the UBI container will corrupt the rootfs.
- **`boot_a.bin` / `boot_b.bin` / `rootfs_a.bin`**: These are backups dumped from a working router using `mtk.py rp`. Use these if you want to restore the exact state of a working device.

### About the custom DA loader

The stock mtkclient DA loaders (`MTK_AllInOne_DA_*.bin`) do **not** work with the ZLT-X28's NAND configuration. This package includes a custom DA (`DA_BR.bin`) extracted from the Quectel RG500L-EU firmware package (version `gem-mp-1907-mp1.V1.27_QUECTEL_1907MP1_RG500L_P38`, built 2023-06-28).

This DA:
- Supports NAND flash with PMT partition tables
- Supports `CMD:READ-PARTITION` and `CMD:WRITE-PARTITION` (name-based access)
- Has a 26MB per-session read limit (handled by the patch's batched reads)
- Uses Thumb-mode ARM instructions (handled by the patch's Thumb decoders)

**Source**: The DA was obtained from the Quectel RG500L-EU-AC QuecOpen firmware package (`RG500LEUACR04A06M8G_OCPU_30.202.30.202`). See GitHub issue [#88 on bkerler/mtkclient](https://github.com/bkerler/mtkclient/issues/88) for background.

---

## Step 1: Clone and Patch mtkclient

```bash
# Clone upstream mtkclient
git clone https://github.com/bkerler/mtkclient.git
cd mtkclient

# Install dependencies
pip3 install -r requirements.txt

# Apply the ZLT-X28 patch
/path/to/zlt-x28-unbrick/apply_patch.sh .
```

The script will:
1. Apply `zlt_x28_nand_support.patch` to the mtkclient source
2. Copy the custom DA loader to `download_agent/`
3. Copy the scatter file to the mtkclient root

### Manual patching (if script fails)

```bash
cd mtkclient
git apply /path/to/zlt-x28-unbrick/zlt_x28_nand_support.patch
cp /path/to/zlt-x28-unbrick/da_loader/DA_BR.bin download_agent/
cp /path/to/zlt-x28-unbrick/MT6890_ZLT_X28_scatter.xml .
```

---

## Step 2: Connect the Router

### Entering BROM mode

1. Power off the router (disconnect power)
2. Hold the **Reset button** (on the rear panel, small pinhole)
3. While holding Reset, connect the USB cable to your computer
4. Keep holding Reset for 5 seconds, then release
5. The router should be detected as "MT65xx Preloader" USB device

### Linux USB setup

```bash
# Stop modemmanager from interfering
sudo systemctl stop ModemManager

# Add udev rules (if not already present)
sudo bash -c 'echo "SUBSYSTEM==\"usb\", ATTR{idVendor}==\"0e8d\", ATTR{idProduct}==\"2000\", MODE=\"0666\"" > /etc/udev/rules.d/99-mtk.rules'
sudo bash -c 'echo "SUBSYSTEM==\"usb\", ATTR{idVendor}==\"0e8d\", ATTR{idProduct}==\"0001\", MODE=\"0666\"" >> /etc/udev/rules.d/99-mtk.rules'
sudo udevadm control --reload-rules
```

### macOS USB setup

No special drivers needed. macOS should detect the device automatically. If you see permission errors:
```bash
sudo python3 mtk.py --loader download_agent/DA_BR.bin printgpt
```

---

## Step 3: Read Partition Table

Verify the connection and see all partitions:

```bash
python3 mtk.py --loader download_agent/DA_BR.bin printgpt
```

You should see output like:
```
Partition table (PMT):
  preloader            start=0x00000000  size=0x00400000
  preloader_backup     start=0x00400000  size=0x00200000
  lk                   start=0x00600000  size=0x00100000
  boot                 start=0x00700000  size=0x00a00000
  tee                  start=0x01100000  size=0x00080000
  ...
```

If you see `Waiting for PreLoader VCOM`, the router isn't in BROM mode. Reconnect with Reset held.

---

## Step 4: Backup Current Partitions (IMPORTANT)

Before flashing anything, backup your current partitions:

```bash
# Backup all partitions to a directory
mkdir -p backup
python3 mtk.py --loader download_agent/DA_BR.bin rf backup
```

Or backup individual critical partitions:

```bash
python3 mtk.py --loader download_agent/DA_BR.bin rp boot_a backup/boot_a.bin
python3 mtk.py --loader download_agent/DA_BR.bin rp boot_b backup/boot_b.bin
python3 mtk.py --loader download_agent/DA_BR.bin rp rootfs backup/rootfs.bin
```

**Keep these backups safe.** If anything goes wrong, you can flash them back.

---

## Step 5: Flash Partitions

### The actual recovery commands used

This is exactly what was done to recover a locked-out ZLT-X28:

```bash
# Flash stock boot image to boot_b partition
python3 mtk.py w boot_b /path/to/firmware/boot-stock.img --loader download_agent/DA_BR.bin

# Flash stock UBI rootfs to rootfs partition
python3 mtk.py w rootfs /path/to/firmware/ubi-rootfs-stock.ubi --loader download_agent/DA_BR.bin
```

### Full recovery (all partitions)

If you need to flash everything, you'll need the complete Quectel firmware package. The stock images in this package cover the two most critical partitions (boot + rootfs). For a full flash, obtain the Quectel RG500L-EU-AC QuecOpen firmware package and use the scatter file:

```bash
python3 mtk.py --loader download_agent/DA_BR.bin wf MT6890_ZLT_X28_scatter.xml
```

### Flash individual partitions

```bash
# Flash stock boot to boot_b (or boot_a)
python3 mtk.py w boot_b firmware/boot-stock.img --loader download_agent/DA_BR.bin

# Flash stock rootfs (UBI format)
python3 mtk.py w rootfs firmware/ubi-rootfs-stock.ubi --loader download_agent/DA_BR.bin

# Restore from backup dumps
python3 mtk.py w boot_a firmware/boot_a.bin --loader download_agent/DA_BR.bin
python3 mtk.py w rootfs firmware/rootfs_a.bin --loader download_agent/DA_BR.bin
```

### Common recovery scenarios

#### Scenario 1: Locked out of web UI (services disabled)
This is the exact scenario that was recovered. Flash stock boot + rootfs:
```bash
python3 mtk.py w boot_b firmware/boot-stock.img --loader download_agent/DA_BR.bin
python3 mtk.py w rootfs firmware/ubi-rootfs-stock.ubi --loader download_agent/DA_BR.bin
```

#### Scenario 2: Router doesn't boot
Flash both boot slots + rootfs:
```bash
python3 mtk.py w boot_a firmware/boot-stock.img --loader download_agent/DA_BR.bin
python3 mtk.py w boot_b firmware/boot-stock.img --loader download_agent/DA_BR.bin
python3 mtk.py w rootfs firmware/ubi-rootfs-stock.ubi --loader download_agent/DA_BR.bin
```

#### Scenario 3: Boot loop after firmware update
```bash
python3 mtk.py w boot_b firmware/boot-stock.img --loader download_agent/DA_BR.bin
python3 mtk.py w rootfs firmware/ubi-rootfs-stock.ubi --loader download_agent/DA_BR.bin
python3 mtk.py --loader download_agent/DA_BR.bin reboot
```

#### Scenario 4: Full factory restore
Flash all partitions using the Quectel firmware package + scatter file:
```bash
python3 mtk.py --loader download_agent/DA_BR.bin wf MT6890_ZLT_X28_scatter.xml
```

---

## Step 6: Reboot and Verify

After flashing, reboot the router:

```bash
python3 mtk.py --loader download_agent/DA_BR.bin reboot
```

The router should reboot normally. Verify:
1. Wait 60-90 seconds for full boot
2. Check if Wi-Fi SSID appears
3. Connect to `192.168.0.1` via Ethernet or Wi-Fi
4. Login with default credentials (admin/admin)

---

## Troubleshooting

### "Waiting for PreLoader VCOM" — device not detected

- Make sure you're using a **data** USB cable, not charge-only
- Try a different USB port (avoid USB hubs)
- On Linux: `lsusb | grep 0e8d` — should show MediaTek device
- Hold Reset longer (10 seconds) while connecting
- Try without holding Reset — some units enter BROM automatically when boot fails

### `AttributeError: 'bool' object has no attribute 'decode'`

The patch wasn't applied correctly. Re-run `apply_patch.sh`.

### `AttributeError: 'list' object has no attribute 'name'`

Same as above — the PMT list handling patch is missing.

### Read fails after 26MB ("DA stopped accepting commands")

This is expected behavior for partitions larger than 26MB. The patch adds automatic batching. If you still see this, ensure `xml_lib.py` was patched correctly:

```bash
grep "DA_BATCH_LIMIT" mtkclient/Library/DA/xmlflash/xml_lib.py
```

Should return a match. If not, re-apply the patch.

### `git apply` fails with "patch does not apply"

Your mtkclient version may have diverged. Try:
```bash
git checkout .
git pull origin main
git apply --reject zlt_x28_nand_support.patch
# Manually resolve *.rej files
```

Or use the `patch` command:
```bash
patch -p1 < zlt_x28_nand_support.patch
```

### USB disconnects during flash

- Use a powered USB hub if your computer's USB port is underpowered
- Try a shorter USB cable
- Don't use USB-C to USB-A adapters if possible — use a native port
- On Linux, disable USB autosuspend:
  ```bash
  echo -1 > /sys/module/usbcore/parameters/autosuspend
  ```

### Router still doesn't boot after flashing

1. Try flashing both boot slots:
   ```bash
   python3 mtk.py w boot_a firmware/boot-stock.img --loader download_agent/DA_BR.bin
   python3 mtk.py w boot_b firmware/boot-stock.img --loader download_agent/DA_BR.bin
   ```
2. Flash rootfs again:
   ```bash
   python3 mtk.py w rootfs firmware/ubi-rootfs-stock.ubi --loader download_agent/DA_BR.bin
   ```
3. Reboot:
   ```bash
   python3 mtk.py --loader download_agent/DA_BR.bin reboot
   ```

### "No da_loader config set up"

The DA loader wasn't found. Ensure:
```bash
ls download_agent/DA_BR.bin
```
If missing, copy it from this package:
```bash
cp /path/to/zlt-x28-unbrick/da_loader/DA_BR.bin download_agent/
```

### Wrong firmware files — raw images vs NAND partition images

**Do NOT use the raw Quectel OpenWrt images** (`boot.img` 9MB, `root.squashfs` 24MB) for NAND flashing. These are raw images without NAND padding or UBI containers.

**Always use full partition-sized images**:
- `boot-stock.img` (33MB) for boot partitions
- `ubi-rootfs-stock.ubi` (64MB) for rootfs partition

If you only have raw images, you need to convert them:
- Boot: pad to 33MB (0x2000000) with zeros
- Rootfs: create a UBI container around the squashfs using `ubinize`

---

## Firmware Information

- **Platform**: MT6890 (MediaTek T750)
- **Modem**: Quectel RG500L-EU-AC
- **Firmware version**: `gem-mp-1907-mp1.V1.27_QUECTEL_1907MP1_RG500L_P38`
- **Build date**: 2023-05-31
- **Storage**: NAND, block size 0x40000 (256KB)
- **Flash size**: ~1GB (1,072,693,248 bytes)
- **Project**: `evb6890v1_64_cpe_nand`
- **DA version**: `MTK_DA_v6_2023-06-28 04:13:19`

### Key partition sizes

| Partition | Size | Image file |
|---|---|---|
| boot_a | 33MB (0x2000000) | `boot-stock.img` or `boot_a.bin` |
| boot_b | 33MB (0x2000000) | `boot-stock.img` or `boot_b.bin` |
| rootfs | 64MB (0x4000000) | `ubi-rootfs-stock.ubi` or `rootfs_a.bin` |

---

## Technical Details: What the Patch Does

For a full technical breakdown, see `CHANGES_REPORT.md` in the mtkclient directory after patching, or read the patch file directly.

### Key changes (10 files, +554/-148 lines)

1. **NAND/PMT support** (`mtk_daloader.py`, `mtk_da_handler.py`, `storage.py`): Routes partition operations through PMT instead of GPT for NAND devices. Adds name-based read/write.

2. **DA batch reads** (`xml_lib.py`): Splits large reads into 26MB batches. Adds `readflash_by_name()` and `writeflash_by_name()` using `CMD:READ-PARTITION`/`CMD:WRITE-PARTITION`.

3. **Thumb-mode DA patching** (`arm_tools.py`, `arch.py`, `v6.py`): Adds Thumb instruction decoders for the DA2 binary patcher. Replaces `assert` crashes with graceful warnings.

4. **Misc fixes** (`thread_handling.py`, `daconfig.py`, `xml_cmd.py`): Append-mode file writes, DA loader fallback, write-partition XML command.

---

## Credits

- Original mtkclient by [bkerler](https://github.com/bkerler/mtkclient)
- NAND/PMT patches based on findings from [GitHub issue #88](https://github.com/bkerler/mtkclient/issues/88) by @gaglians
- Custom DA loader from Quectel RG500L-EU-AC QuecOpen firmware package (`RG500LEUACR04A06M8G_OCPU_30.202.30.202`)
- Stock boot/rootfs images extracted from the same Quectel firmware package

---

## License

This recovery package is provided as-is for educational and repair purposes. The mtkclient patches are subject to mtkclient's license (GPLv3). The DA loader and firmware files are property of Quectel/MediaTek and are included for device recovery only.
