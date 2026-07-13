#!/bin/bash
# apply_patch.sh — Patches mtkclient for ZLT-X28 (MT6890 NAND) support
# Usage: ./apply_patch.sh [path_to_mtkclient]
# If no path given, assumes mtkclient is in current directory or parent

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/zlt_x28_nand_support.patch"

# Find mtkclient directory
if [ -n "$1" ]; then
    MTK_DIR="$1"
elif [ -d "$(pwd)/mtkclient" ] && [ -f "$(pwd)/mtkclient/mtk.py" ]; then
    MTK_DIR="$(pwd)"
elif [ -f "$(pwd)/mtk.py" ]; then
    MTK_DIR="$(pwd)"
else
    echo "Usage: $0 [path_to_mtkclient]"
    echo "Please provide the path to your mtkclient clone."
    echo "Example: $0 /home/user/mtkclient"
    exit 1
fi

echo "=== ZLT-X28 mtkclient Patcher ==="
echo "mtkclient dir: $MTK_DIR"
echo "Patch file:    $PATCH_FILE"
echo ""

# Verify mtkclient
if [ ! -f "$MTK_DIR/mtk.py" ]; then
    echo "ERROR: $MTK_DIR/mtk.py not found. Is this a valid mtkclient directory?"
    exit 1
fi

# Check if already patched
if grep -q "readflash_by_name" "$MTK_DIR/mtkclient/Library/DA/mtk_daloader.py" 2>/dev/null; then
    echo "WARNING: mtkclient appears to already be patched."
    read -p "Re-apply patch anyway? (y/N) " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 0
    fi
    # Revert first
    cd "$MTK_DIR"
    git checkout -- mtkclient/Library/ 2>/dev/null || true
    echo "Reverted existing changes."
fi

# Apply patch
cd "$MTK_DIR"
echo "Applying patch..."
if git apply --check "$PATCH_FILE" 2>/dev/null; then
    git apply "$PATCH_FILE"
    echo "SUCCESS: Patch applied cleanly."
elif patch -p1 --dry-run < "$PATCH_FILE" 2>/dev/null; then
    patch -p1 < "$PATCH_FILE"
    echo "SUCCESS: Patch applied (via patch command)."
else
    echo "ERROR: Patch did not apply cleanly. Trying with --reject option..."
    git apply --reject "$PATCH_FILE" 2>/dev/null || true
    echo "Patch applied with possible rejects. Check *.rej files for conflicts."
    echo "You may need to manually apply rejected hunks."
fi

# Copy DA loader
echo ""
echo "=== DA Loader Setup ==="
DA_DIR="$MTK_DIR/download_agent"
if [ ! -d "$DA_DIR" ]; then
    mkdir -p "$DA_DIR"
fi

cp "$SCRIPT_DIR/da_loader/DA_BR.bin" "$DA_DIR/"
cp "$SCRIPT_DIR/da_loader/DA_BR_unsign.bin" "$DA_DIR/"
cp "$SCRIPT_DIR/da_loader/flash.xml" "$DA_DIR/"
cp "$SCRIPT_DIR/da_loader/flash.xsd" "$DA_DIR/" 2>/dev/null || true
echo "DA loader copied to: $DA_DIR/"

# Copy scatter file
cp "$SCRIPT_DIR/MT6890_ZLT_X28_scatter.xml" "$MTK_DIR/"
echo "Scatter file copied to: $MTK_DIR/MT6890_ZLT_X28_scatter.xml"

echo ""
echo "=== Done! ==="
echo "Next steps:"
echo "  1. Install mtkclient dependencies: pip3 install -r requirements.txt"
echo "  2. Connect your ZLT-X28 via USB (hold reset button while powering on for BROM mode)"
echo "  3. Read partition table: python3 mtk.py --loader download_agent/DA_BR.bin printgpt"
echo "  4. See RECOVERY_GUIDE.md for full instructions"
