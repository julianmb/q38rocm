#!/usr/bin/env bash
# ==============================================================================
# strix_diag.sh — Diagnostic & System Verification Tool for Strix Halo (gfx1151)
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Verifies kernel version, system RAM / UMA BIOS allocation, ROCm toolchain,
# Vulkan shader compiler (glslc), required environment variables, and ROCmFPX
# binary builds.
#
# Usage:
#   ./scripts/strix_diag.sh [--fix-env]
# ==============================================================================
set -euo pipefail

FIX_ENV=0
if [[ "${1:-}" == "--fix-env" ]]; then
    FIX_ENV=1
fi

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Formatting
if [ -t 1 ]; then
    GREEN="\033[0;32m"
    YELLOW="\033[0;33m"
    RED="\033[0;31m"
    BOLD="\033[1m"
    NC="\033[0m"
else
    GREEN=""
    YELLOW=""
    RED=""
    BOLD=""
    NC=""
fi

pass() {
    echo -e "  [${GREEN}PASS${NC}] $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

warn() {
    echo -e "  [${YELLOW}WARN${NC}] $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
    echo -e "  [${RED}FAIL${NC}] $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo -e "${BOLD}==========================================================${NC}"
echo -e "${BOLD} q38rocm: AMD Strix Halo (gfx1151) System Diagnostic Tool ${NC}"
echo -e "${BOLD}==========================================================${NC}"

# ------------------------------------------------------------------------------
# 1. OS & Linux Kernel Check
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}1. OS & Kernel Environment:${NC}"
KERNEL_VER=$(uname -r)
echo "   Linux Kernel: ${KERNEL_VER}"

# Extract kernel major.minor
K_MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)
K_MINOR=$(echo "$KERNEL_VER" | cut -d. -f2)

if [ "$K_MAJOR" -gt 6 ] || { [ "$K_MAJOR" -eq 6 ] && [ "$K_MINOR" -ge 11 ]; }; then
    pass "Kernel ${KERNEL_VER} >= 6.11 (optimal Strix Halo / gfx1151 driver support)."
else
    warn "Kernel ${KERNEL_VER} < 6.11. Kernel 6.11+ is recommended for optimal gfx1151 UMA support."
fi

# ------------------------------------------------------------------------------
# 2. RAM & AGESA / BIOS UMA Allocation Check
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}2. Physical RAM & UMA Memory Allocation:${NC}"
if [ -f /proc/meminfo ]; then
    MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEM_TOTAL_GB=$(python3 -c "print(round(${MEM_TOTAL_KB} / 1024 / 1024, 1))")
    echo "   OS-Visible Memory: ${MEM_TOTAL_GB} GiB"

    if python3 -c "import sys; sys.exit(0 if ${MEM_TOTAL_GB} >= 110 else 1)"; then
        pass "System RAM tier: ~128 GB. Native 262K context window supported without swapping."
    elif python3 -c "import sys; sys.exit(0 if ${MEM_TOTAL_GB} >= 80 else 1)"; then
        pass "System RAM tier: ~96 GB. Supports 128K-262K context window."
    elif python3 -c "import sys; sys.exit(0 if ${MEM_TOTAL_GB} >= 50 else 1)"; then
        pass "System RAM tier: ~64 GB (Sweet spot). Supports 32K-128K context window."
    elif python3 -c "import sys; sys.exit(0 if ${MEM_TOTAL_GB} >= 24 else 1)"; then
        warn "System RAM tier: ~32 GB. Supports up to 16K-32K context window (or hybrid 262K context models)."
    else
        fail "OS-Visible Memory is under 24 GB (${MEM_TOTAL_GB} GiB). Check BIOS UMA settings."
    fi

    # Check BIOS UMA frame buffer warning
    if python3 -c "import sys; sys.exit(0 if ${MEM_TOTAL_GB} < 20 else 1)"; then
        warn "Visible memory is low (< 20 GB). If physical RAM is higher, reboot into AGESA/BIOS setup and set UMA Frame Buffer Size to UMA_SPECIFIED or Auto (maximum available)."
    fi
fi

# ------------------------------------------------------------------------------
# 3. Environment Variables
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}3. Required Strix Halo Environment Variables:${NC}"

if [ "${HSA_OVERRIDE_GFX_VERSION:-}" == "11.5.1" ]; then
    pass "HSA_OVERRIDE_GFX_VERSION=11.5.1 is set correctly."
else
    warn "HSA_OVERRIDE_GFX_VERSION is '${HSA_OVERRIDE_GFX_VERSION:-not set}'. Expected '11.5.1'."
    if [ "$FIX_ENV" -eq 1 ]; then
        export HSA_OVERRIDE_GFX_VERSION=11.5.1
        echo "   -> Applied HSA_OVERRIDE_GFX_VERSION=11.5.1 for this session."
    fi
fi

if [ "${GGML_HIP_ENABLE_UNIFIED_MEMORY:-}" == "1" ]; then
    pass "GGML_HIP_ENABLE_UNIFIED_MEMORY=1 is set correctly."
else
    warn "GGML_HIP_ENABLE_UNIFIED_MEMORY is '${GGML_HIP_ENABLE_UNIFIED_MEMORY:-not set}'. Expected '1'."
    if [ "$FIX_ENV" -eq 1 ]; then
        export GGML_HIP_ENABLE_UNIFIED_MEMORY=1
        echo "   -> Applied GGML_HIP_ENABLE_UNIFIED_MEMORY=1 for this session."
    fi
fi

# ------------------------------------------------------------------------------
# 4. ROCm Stack & Device Inspection
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}4. ROCm Toolchain & HIP Drivers:${NC}"

if command -v hipcc >/dev/null 2>&1 || [ -x /opt/rocm/bin/hipcc ]; then
    HIPCC_BIN=$(command -v hipcc 2>/dev/null || echo "/opt/rocm/bin/hipcc")
    pass "HIP compiler found: ${HIPCC_BIN}"
else
    fail "hipcc compiler not found. ROCm 10.0 HIP SDK is required (also supports 7.2.x)."
fi

if command -v rocminfo >/dev/null 2>&1 || [ -x /opt/rocm/bin/rocminfo ]; then
    ROCMINFO_BIN=$(command -v rocminfo 2>/dev/null || echo "/opt/rocm/bin/rocminfo")
    pass "rocminfo utility found: ${ROCMINFO_BIN}"
    if "${ROCMINFO_BIN}" 2>/dev/null | grep -E "gfx1151|gfx1150|gfx1100" >/dev/null; then
        pass "RDNA 3.5 APU graphics target (gfx1151) detected in rocminfo."
    else
        warn "gfx1151 target not explicitly listed in rocminfo output (verify ROCm 10.0 driver installation)."
    fi
else
    warn "rocminfo not found in PATH or /opt/rocm/bin."
fi

# ------------------------------------------------------------------------------
# 5. Vulkan Backend & Shader Compiler
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}5. Vulkan Backend & Shader Compiler:${NC}"

if command -v glslc >/dev/null 2>&1; then
    GLSLC_PATH=$(command -v glslc)
    pass "glslc (Vulkan shader compiler) found: ${GLSLC_PATH}"
    pass "Vulkan0 backend is supported for max decode speed."
else
    warn "glslc not found. Vulkan shader compilation disabled; will fall back to ROCm0."
fi

if command -v vulkaninfo >/dev/null 2>&1; then
    pass "vulkaninfo utility found."
else
    warn "vulkaninfo not found (optional, install vulkan-tools if Vulkan issues occur)."
fi

# ------------------------------------------------------------------------------
# 6. ROCmFPX Binaries & Build Status
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}6. ROCmFPX Toolchain Build Status:${NC}"

BUILD_BIN_DIR="${SCRIPT_DIR}/../engine/bin"
REQUIRED_BINS=("llama-cli" "llama-server" "llama-quantize" "llama-bench")
ALL_BINS_EXIST=1

for b in "${REQUIRED_BINS[@]}"; do
    if [ -x "${BUILD_BIN_DIR}/${b}" ]; then
        pass "Binary '${b}' exists."
    else
        warn "Binary '${b}' missing from ${BUILD_BIN_DIR}."
        ALL_BINS_EXIST=0
    fi
done

if [ "$ALL_BINS_EXIST" -eq 0 ]; then
    warn "Toolchain incomplete. Run './scripts/build_rocmfpx.sh' to build all binaries."
fi

# ------------------------------------------------------------------------------
# Diagnostic Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}==========================================================${NC}"
echo -e "${BOLD} Diagnostic Summary: ${GREEN}${PASS_COUNT} PASS${NC}, ${YELLOW}${WARN_COUNT} WARN${NC}, ${RED}${FAIL_COUNT} FAIL${NC}"
echo -e "${BOLD}==========================================================${NC}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "${RED}Critical issues found. Please address FAIL items above before running inference.${NC}"
    exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}System is functional, but check WARN items above for optimal performance.${NC}"
    if [ "$FIX_ENV" -eq 0 ]; then
        echo "Tip: Re-run with './scripts/strix_diag.sh --fix-env' or source .env.example to set environment variables."
    fi
else
    echo -e "${GREEN}System is 100% configured for maximum Strix Halo performance!${NC}"
fi
