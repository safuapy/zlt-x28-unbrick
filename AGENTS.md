# AGENTS.md

> Context file for AI coding agents working with the ZLT-X28 recovery package.

## Project Overview

This is a recovery toolkit for the **ZLT-X28 5G CPE router** (MediaTek MT6890 / Quectel RG500L-EU). The router uses **NAND flash with PMT** (Partition Management Table), which upstream `mtkclient` does not support. This package contains patches, a custom Download Agent, stock firmware images, and documentation to recover bricked/locked devices.

## Key Facts

- **SoC**: MediaTek MT6890 (T750 platform)
- **Modem**: Quectel RG500L-EU-AC
- **Storage**: NAND, 256KB block size, ~1GB total
- **Partition table**: PMT (not GPT)
- **Firmware version**: `gem-mp-1907-mp1.V1.27_QUECTEL_1907MP1_RG500L_P38` (built 2023-05-31)
- **DA**: `DA_BR.bin` — custom Download Agent from Quectel firmware, v6, built 2023-06-28
- **DA architecture**: ARM Thumb (16/32-bit mixed instructions)
- **DA read batch limit**: 0x1A00000 (26MB) per session
- **Flash size**: 1,072,693,248 bytes
- **Router IP**: 192.168.0.1 (default)
- **Default creds**: admin/admin

## File Map

```
zlt-x28-unbrick/
├── AGENTS.md                     ← this file
├── README.md                     ← quick start for humans
├── RECOVERY_GUIDE.md             ← full step-by-step guide + troubleshooting
├── apply_patch.sh                ← automated patch script (bash)
├── zlt_x28_nand_support.patch    ← git patch for bkerler/mtkclient
├── MT6890_ZLT_X28_scatter.xml    ← NAND partition layout (stock)
├── MT6890_openwrt_scatter.xml    ← NAND partition layout (OpenWrt)
├── da_loader/
│   ├── DA_BR.bin                 ← signed Download Agent (381,660 bytes, MD5: 54500f76...)
│   ├── DA_BR_unsign.bin          ← unsigned DA (same size)
│   ├── flash.xml                 ← DA flash config (project: evb6890v1_64_cpe_nand)
│   └── flash.xsd                 ← DA flash schema
└── firmware/
    ├── boot-stock.img            ← STOCK boot (33MB, full NAND partition, MD5: 0426d9cd...)
    ├── ubi-rootfs-stock.ubi      ← STOCK rootfs (64MB, UBI container, MD5: 7d08485e...)
    ├── root_ro-stock.sig         ← root_ro signature (3,680 bytes)
    ├── boot_a.bin                ← backup dump of boot_a (33MB)
    ├── boot_b.bin                ← backup dump of boot_b (33MB)
    └── rootfs_a.bin              ← backup dump of rootfs (64MB)
```

## What the Patch Does (10 files, +554/-148 lines)

Patches `bkerler/mtkclient` (commit `a6a7147`) in 4 areas:

### 1. NAND/PMT Support
- `mtk_daloader.py`: `partition_table_category()` returns `"PMT"` for NAND. `detect_partition()` actually searches PMT entries by name (upstream returned the whole list). New `readflash_by_name()` / `writeflash_by_name()` wrappers.
- `mtk_da_handler.py`: Read/write paths use by-name access for NAND. `printgpt` handles PMT list. Handles `guid_gpt` as list.
- `storage.py`: Off-by-one fix — trims read length by one block when `length == flashsize` (DA boundary check bug).

### 2. DA XML Protocol
- `xml_lib.py`: `readflash()` rewritten to batch reads at 0x1A00000. New `readflash_by_name()` via `CMD:READ-PARTITION`. New `writeflash_by_name()` via `CMD:WRITE-PARTITION` with FileSysOp handshake. PMT `PartitionTable` field name fix. SLA bool guard.
- `xml_cmd.py`: New `cmd_write_partition_by_name()` emits `WRITE-PARTITION` XML.

### 3. Thumb-mode DA Patching
- `arm_tools.py`: Thumb instruction decoders (`decode_thumb_ldr_literal`, `is_thumb_prologue`, etc.). `find_string_xref()` and `find_function_start_from_off()` scan Thumb instructions.
- `arch.py`: None guard in `get_next_bl_from_off()`.
- `v6.py`: All `assert` replaced with warnings + skip. 32-bit DA2 path gets `partial_protect` + policy patches. Null checks on all BL chain calls.

### 4. Misc
- `thread_handling.py`: `writedata()` accepts `mode` param for append mode.
- `daconfig.py`: Fallback to scanning loader dir when specified DA not found. Preserve custom loader in `setup()`.

## Critical Warnings

1. **Do NOT flash raw Quectel OpenWrt images** (9MB `boot.img`, 24MB `root.squashfs`) to NAND. They lack padding and UBI containers. Always use full partition-sized images (`boot-stock.img` 33MB, `ubi-rootfs-stock.ubi` 64MB).

2. **Always backup before flashing**: `python3 mtk.py rp <partition> backup/<name>.bin --loader download_agent/DA_BR.bin`

3. **The DA must be specified explicitly**: `--loader download_agent/DA_BR.bin`. The stock mtkclient DAs do not work.

4. **Tested on one device only.** Use at your own risk.

## Recovery Commands (What Actually Worked)

```bash
# Enter BROM mode: hold Reset + connect USB
# Verify connection:
python3 mtk.py --loader download_agent/DA_BR.bin printgpt

# Backup:
python3 mtk.py rp boot_a backup/boot_a.bin --loader download_agent/DA_BR.bin
python3 mtk.py rp boot_b backup/boot_b.bin --loader download_agent/DA_BR.bin
python3 mtk.py rp rootfs backup/rootfs.bin --loader download_agent/DA_BR.bin

# Flash stock images:
python3 mtk.py w boot_b firmware/boot-stock.img --loader download_agent/DA_BR.bin
python3 mtk.py w rootfs firmware/ubi-rootfs-stock.ubi --loader download_agent/DA_BR.bin

# Reboot:
python3 mtk.py --loader download_agent/DA_BR.bin reboot
```

## Common Errors and Fixes

| Error | Cause | Fix |
|---|---|---|
| `'bool' object has no attribute 'decode'` | Patch not applied | Run `apply_patch.sh` |
| `'list' object has no attribute 'name'` | PMT list handling missing | Re-apply patch |
| `No da_loader config set up` | DA not found | `cp da_loader/DA_BR.bin download_agent/` |
| Read stops at 26MB | DA batch limit | Patch adds batching; check `DA_BATCH_LIMIT` in `xml_lib.py` |
| `assert` crash in v6.py | Thumb DA not supported | Patch adds Thumb decoders; re-apply |
| `Waiting for PreLoader VCOM` | Not in BROM mode | Hold Reset while connecting USB |

## Agent Guidelines

- **Do not modify the patch file** (`zlt_x28_nand_support.patch`) unless the upstream mtkclient has changed and the patch no longer applies. In that case, re-generate from a working mtkclient checkout.
- **Do not swap firmware files**. The `boot-stock.img` (33MB) and `ubi-rootfs-stock.ubi` (64MB) are NAND partition-sized. Raw OpenWrt images will not work.
- **Always use `--loader download_agent/DA_BR.bin`** in all mtkclient commands. Without it, mtkclient tries stock DAs that don't support NAND/PMT.
- **The scatter file** (`MT6890_ZLT_X28_scatter.xml`) is only needed for full-flash (`wf`) operations. Individual partition read/write (`rp`/`w`) uses partition names directly.
- **Partition names** on this device: `preloader`, `preloader_backup`, `lk`, `boot_a`, `boot_b`, `tee`, `dpm`, `loader_ext`, `mcupm`, `medmcu`, `dsp`, `pi_img`, `sspm`, `spmfw`, `modem`, `rootfs`, `MCF_OTA_1`, `MCF_OTA_2`.

## References

- Upstream: https://github.com/bkerler/mtkclient
- Issue #88 (MT6890 NAND): https://github.com/bkerler/mtkclient/issues/88
- Quectel RG500L-EU-AC QuecOpen firmware: `RG500LEUACR04A06M8G_OCPU_30.202.30.202`
- Unlock guide (firmware 1.5.13 only): https://github.com/mahdigh782/Unlock-ZLT-X28
