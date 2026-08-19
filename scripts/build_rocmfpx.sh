#!/usr/bin/env bash
# ==============================================================================
# build_rocmfpx.sh — Automated Toolchain Installer for AMD Strix Halo (gfx1151)
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo " q38rocm: ROCmFPX Toolchain Installer for Strix Halo       "
echo "=========================================================="

# 1. Dependency Checks
if ! command -v cmake &> /dev/null; then
    echo "Error: cmake is required but not installed."
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "Error: git is required but not installed."
    exit 1
fi

# Check for ROCm/HIP
if ! command -v hipcc &> /dev/null && ! [ -x /opt/rocm/bin/hipcc ]; then
    echo "Error: ROCm/HIP toolchain not found."
    echo "       Please install ROCm 7.2.x before continuing."
    exit 1
fi

# 2. Clone or Update pinned ROCmFPX repository
PINNED_COMMIT="0fc9568e07ccc8553010864cb8db1957e629cbfa"

if [ ! -d "ROCmFPX/.git" ]; then
    echo "[*] Cloning charlie12345/ROCmFPX repository..."
    git clone https://github.com/charlie12345/ROCmFPX.git
fi

cd ROCmFPX
echo "[*] Checking out pinned commit ($PINNED_COMMIT)..."
git fetch origin
git checkout "$PINNED_COMMIT"

# 3. Execute Build
echo "[*] Building ROCmFPX binaries for AMD Strix Halo (gfx1151)..."
env JOBS=$(nproc) ./scripts/build-strix-rocmfp4-mtp.sh

echo "=========================================================="
echo " Build Complete!"
echo " Binaries located at: ROCmFPX/build-strix-rocmfp4/bin/"
echo "=========================================================="
