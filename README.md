# ZLT-X28 Unbrick & Recovery

Complete recovery toolkit for bricked/locked ZLT-X28 5G routers (MediaTek MT6890 / Quectel RG500L-EU).

## My Recovery Story

My ZLT-X28 got bricked after an AI agent configured it via SSH and disabled critical services (lanmgr, dhcp) — locking everyone out. Wi-Fi didn't broadcast, LAN port didn't respond, but the router lights were on and it still connected to 4G with a data SIM.

Here's how I fixed it:

1. **Flashed stock images** (boot + rootfs) provided by [@bnjdg](https://github.com/bkerler/mtkclient/issues/88) using mtkclient. I used `DA_BR.bin` from the Quectel RG500L-EU-AC QuecOpen firmware package — the stock mtkclient DAs don't work with this NAND device. I also had to use a patched mtkclient (upstream crashes on MT6890 NAND due to missing PMT support, Thumb-mode DA patching, and a 26MB DA read batch limit). Patch is included in this repo.

2. **After flashing**, the router booted and the web UI was accessible.

3. **Updated firmware to 1.5.13** via admin panel → System Update, using the firmware from [Mr-Tezar/ZLT-X28-Firmware-1.5.13-simLock](https://github.com/Mr-Tezar/ZLT-X28-Firmware-1.5.13-simLock). After the update the modem was locked (expected — the unlock script fixes this later).

4. **Enabled Telnet/SSH** via the command injection method described in the repo (DMZ IP field injection or the curl API method). Note: the router IP may change after the 1.5.13 update.

5. **SSH'd in** (`ssh -o HostKeyAlgorithms=+ssh-rsa admin@<router_ip>`, password: `admin`), transferred the unlock script (`x28` + `x28.tgz`) via SCP, ran it, and did a factory reset.

6. Router rebooted unlocked — works with any SIM/network now.

**Tip**: If you're trying to get shell via UART, `picocom` works better than `minicom` on Linux.

The command injection only works on 1.5.13 — it does NOT work on older versions (I tried on the stock firmware first, got `NO_AUTH` / no effect). So the flow is: flash stock → boot → update to 1.5.13 → inject → SSH → unlock → factory reset.

Big thanks to [@gaglians](https://github.com/bkerler/mtkclient/issues/88) and [@bnjdg](https://github.com/bkerler/mtkclient/issues/88) for the dumps and images that made this possible.

---

## Quick Start

```bash
# 1. Clone mtkclient
git clone https://github.com/bkerler/mtkclient.git
cd mtkclient
pip3 install -r requirements.txt

# 2. Apply patch
/path/to/zlt-x28-unbrick/apply_patch.sh .

# 3. Connect router in BROM mode (hold Reset + USB)
# 4. Read partition table
python3 mtk.py --loader download_agent/DA_BR.bin printgpt

# 5. Flash stock boot + rootfs
python3 mtk.py w boot_b firmware/boot-stock.img --loader download_agent/DA_BR.bin
python3 mtk.py w rootfs firmware/ubi-rootfs-stock.ubi --loader download_agent/DA_BR.bin

# 6. Reboot
python3 mtk.py --loader download_agent/DA_BR.bin reboot
```

## Contents

- `RECOVERY_GUIDE.md` — Full step-by-step guide with troubleshooting
- `AGENTS.md` — Context file for AI coding agents
- `apply_patch.sh` — Automated patching script
- `zlt_x28_nand_support.patch` — mtkclient NAND/Thumb/PMT patch (10 files, +554/-148 lines)
- `da_loader/` — Custom Download Agent for MT6890 NAND (from Quectel RG500L-EU firmware)
- `MT6890_ZLT_X28_scatter.xml` — Partition layout
- `firmware/` — Stock partition images:
  - `boot-stock.img` (33MB, full NAND partition)
  - `ubi-rootfs-stock.ubi` (64MB, UBI container with squashfs)
  - `root_ro-stock.sig` — signature file
  - `boot_a.bin`, `boot_b.bin`, `rootfs_a.bin` — backup dumps from working device

## IMPORTANT: Use the right firmware files

**Do NOT use raw Quectel OpenWrt images** (9MB `boot.img`, 24MB `root.squashfs`) for NAND flashing. They lack NAND padding and UBI containers.

**Use the full partition-sized images in `firmware/`**:
- `boot-stock.img` (33MB) for boot_a/boot_b
- `ubi-rootfs-stock.ubi` (64MB) for rootfs

## Why this is needed

Upstream mtkclient doesn't support the ZLT-X28 because:
1. It uses NAND flash with PMT (not GPT)
2. The DA firmware has a 26MB read batch limit
3. The DA2 binary uses ARM Thumb instructions (not ARM32)
4. DA rejects full-flash reads (off-by-one boundary bug)

See `RECOVERY_GUIDE.md` for full details.

## Credits

- Original mtkclient by [bkerler](https://github.com/bkerler/mtkclient)
- NAND/PMT patches based on findings from [GitHub issue #88](https://github.com/bkerler/mtkclient/issues/88) by @gaglians
- Custom DA loader from Quectel RG500L-EU-AC QuecOpen firmware package
- Stock boot/rootfs images provided by @bnjdg
- Unlock guide and 1.5.13 firmware by [Mr-Tezar](https://github.com/Mr-Tezar/ZLT-X28-Firmware-1.5.13-simLock)

## License

This recovery package is provided as-is for educational and repair purposes. The mtkclient patches are subject to mtkclient's license (GPLv3). The DA loader and firmware files are property of Quectel/MediaTek and are included for device recovery only.
