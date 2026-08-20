#!/usr/bin/env bash
# ==============================================================================
# setup_env.sh — Strix Halo (Ryzen AI Max+ 395 / Radeon 8060S / gfx1151)
# Environment Setup for ROCmFPX & Vulkan RADV Wave64 Co-op Matrix Acceleration
# ==============================================================================

# 1. Hardware & Runtime Settings
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export GGML_HIP_ENABLE_UNIFIED_MEMORY=1
export HIP_VISIBLE_DEVICES=0
export ROCM_FLUSH_ACCEPT=1

export AMD_VULKAN_ICD=RADV
export RADV_PERFTEST="gpl,sam,nggc"

# 2. Dynamic Vulkan RADV ICD Discovery (Fedora/Arch/Ubuntu/Debian)
POSSIBLE_ICD_PATHS=(
    "${VK_ICD_FILENAMES:-}"
    "/usr/share/vulkan/icd.d/radeon_icd.x86_64.json"
    "/usr/share/vulkan/icd.d/radeon_icd.json"
    "/usr/share/vulkan/icd.d/radeon_icd.i686.json"
    "/etc/vulkan/icd.d/radeon_icd.json"
    "/etc/vulkan/icd.d/radeon_icd.x86_64.json"
)

for icd in "${POSSIBLE_ICD_PATHS[@]}"; do
    if [ -n "$icd" ] && [ -f "$icd" ]; then
        export VK_ICD_FILENAMES="$icd"
        break
    fi
done

# Find local engine if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSSIBLE_BIN_DIRS=(
    "${ROCMFPX_BIN_DIR:-}"
    "${SCRIPT_DIR}/engine/bin"
    "${SCRIPT_DIR}/../engine/bin"
    "/home/user/source/strix-halo-rocmfpx-hub/engine/bin"
    "/usr/local/bin"
)

for bdir in "${POSSIBLE_BIN_DIRS[@]}"; do
    if [ -n "$bdir" ] && [ -x "${bdir}/llama-server" ]; then
        export PATH="${bdir}:${PATH}"
        export LD_LIBRARY_PATH="${bdir}:${LD_LIBRARY_PATH:-}"
        break
    fi
done

# 3. ROCm Runtime Preflight Check (issue #5: libhipblas.so.3 not found)
# The ROCmFPX engine binaries link against ROCm runtime libraries.
check_rocm_runtime() {
    local needed=(libhipblas.so.3 librocblas.so.5 libamdhip64.so.7)
    local missing=0
    local rocm_home=""
    for d in /opt/rocm /opt/rocm-7.2.3 /opt/rocm-*; do
        if [ -e "${d}/lib/libamdhip64.so.7" ] || [ -e "${d}/lib/libamdhip64.so" ]; then
            rocm_home="$d"
            break
        fi
    done

    if [ -z "$rocm_home" ]; then
        # Probe ldconfig cache instead
        if ! ldconfig -p 2>/dev/null | grep -q "libamdhip64.so.7"; then
            return 2  # ROCm not installed at all
        fi
        return 0
    fi

    export LD_LIBRARY_PATH="${rocm_home}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

    for lib in "${needed[@]}"; do
        if [ -z "$(find "${rocm_home}/lib" -maxdepth 1 -name "${lib}*" 2>/dev/null | head -1)" ]; then
            echo "❌ Missing ROCm library: ${lib}"
            missing=1
        fi
    done
    return $missing
}

if [ -z "${SKIP_ROCM_CHECK:-}" ] && [ "${1:-}" != "--no-rocm-check" ]; then
    if ! check_rocm_runtime; then
        rc=$?
        echo ""
        echo "❌ ROCm runtime missing or incomplete (libhipblas.so.3 etc. not found — issue #5)"
        echo ""
        echo "The ROCmFPX engine binaries link against ROCm runtime libraries that are"
        echo "NOT bundled with this repo. Install ROCm 7.2.x first (one-time setup):"
        echo ""
        if command -v apt-get >/dev/null 2>&1; then
            echo "  Ubuntu 24.04:"
            echo "    curl -fsSL https://repo.radeon.com/amdgpu-install/7.2.3/ubuntu/noble/amdgpu-install_7.2.3.70203-1_all.deb -o /tmp/amdgpu.deb"
            echo "    sudo apt install /tmp/amdgpu.deb && sudo apt-get update"
            echo "    sudo apt-get install --no-install-recommends \\"
            echo "        hip-runtime-amd hipblas rocblas hipblaslt hsa-rocr \\"
            echo "        rocprofiler-register rocsolver roctracer comgr"
        elif command -v dnf >/dev/null 2>&1; then
            echo "  Fedora/RHEL:"
            echo "    sudo dnf install https://repo.radeon.com/amdgpu-install/7.2.3/rhel/9.5/amdgpu-install-7.2.3.70203-1.el9.noarch.rpm"
            echo "    sudo dnf install rocm-dev hip-runtime-amd hipblas rocblas hipblaslt hsa-rocr"
        else
            echo "  See: https://rocm.docs.amd.com/en/latest/deploy/linux/install.html"
        fi
        echo ""
        echo "  Docker users: the Dockerfile installs ROCm automatically — just run docker compose up."
        echo ""
        # Stop launchers (fail fast) but don't kill an interactive shell sourcing this file
        return $rc 2>/dev/null || exit $rc
    fi
fi

echo "✅ Strix Halo ROCmFPX & Vulkan RADV environment successfully configured!"
echo "   • ROCm Target:        gfx1151 (Radeon 8060S 40 CU)"
echo "   • Vulkan ICD:         Mesa RADV (Wave64 + KHR_coopmat)"
echo "   • Unified Memory:     Enabled (128 GB LPDDR5X-8000)"
