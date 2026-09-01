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
    "/home/user/source/halofpx-research/engine/bin"
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
# Supports both ROCm 7.2.x (libhipblas.so.3) and ROCm 10.0+ (libhipblas.so.4).
check_rocm_runtime() {
    local needed_patterns=(libhipblas.so librocblas.so libamdhip64.so)
    local missing=0
    local rocm_home=""
    for d in /opt/rocm/core-10.0 /opt/rocm-10.0* /opt/rocm-10.0 /opt/rocm-7.2.3 /opt/rocm-* /opt/rocm; do
        if [ -e "${d}/lib/libamdhip64.so" ] || [ -e "${d}/lib/libamdhip64.so.7" ] || [ -e "${d}/lib/libamdhip64.so.4" ]; then
            rocm_home="$d"
            break
        fi
    done
    # Fallback: also check via ROCM_PATH/HIP_PATH if set (ROCm 10.0 style)
    if [ -z "$rocm_home" ] && [ -n "${ROCM_PATH:-}" ] && [ -e "${ROCM_PATH}/lib/libamdhip64.so" ]; then
        rocm_home="$ROCM_PATH"
    fi

    if [ -z "$rocm_home" ]; then
        # Probe ldconfig cache instead (support both 7.2 and 10.0 sonames)
        if ! ldconfig -p 2>/dev/null | grep -qE "libamdhip64\.so(\.7|\.4)? "; then
            if ! ldconfig -p 2>/dev/null | grep -q "libamdhip64.so"; then
                return 2  # ROCm not installed at all
            fi
        fi
        return 0
    fi

    export LD_LIBRARY_PATH="${rocm_home}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

    for pat in "${needed_patterns[@]}"; do
        if [ -z "$(find "${rocm_home}/lib" -maxdepth 1 -name "${pat}*" 2>/dev/null | head -1)" ]; then
            echo "❌ Missing ROCm library: ${pat}"
            missing=1
        fi
    done
    return $missing
}

if [ -z "${SKIP_ROCM_CHECK:-}" ] && [ "${1:-}" != "--no-rocm-check" ]; then
    rocm_rc=0
    check_rocm_runtime || rocm_rc=$?
    if [ "$rocm_rc" -ne 0 ]; then
        rc="$rocm_rc"
        echo ""
        echo "❌ ROCm runtime missing or incomplete (ROCm libs not found — issue #5, supports 7.2.x and 10.0)"
        echo ""
        echo "The ROCmFPX engine binaries link against ROCm runtime libraries that are"
        echo "NOT bundled with this repo."
        echo ""
        # Interactive self-install: --install-rocm runs the distro commands directly
        # (issue-class friction: copying 4 install lines was the last manual step)
        if [ "${1:-}" = "--install-rocm" ]; then
            if [ "$(id -u)" -eq 0 ]; then
                SUDO=""
            elif command -v sudo >/dev/null 2>&1; then
                SUDO="sudo"
            else
                echo "❌ --install-rocm needs root or sudo to install packages." >&2
                return $rc 2>/dev/null || exit $rc
            fi
            if command -v apt-get >/dev/null 2>&1; then
                echo "🔧 Installing ROCm 10.0 runtime subset via apt (this downloads ~1.2 GB)..."
                # ROCm 10.0 moved to stable.repo.amd.com with version-prefixed packages
                # (amdrocm10.0-*) and installs to /opt/rocm/core-10.0/. The old
                # repo.radeon.com flat version folders (e.g., .../rocm/apt/10.0/) 404.
                # Setup for Ubuntu 24.04 (noble):
                $SUDO mkdir -p --mode=0755 /etc/apt/keyrings
                curl -fsSL https://stable.repo.amd.com/rocm/gpg/packages.gpg | gpg --dearmor | $SUDO tee /etc/apt/keyrings/amdrocm.gpg > /dev/null || {
                    echo "❌ Failed to fetch ROCm GPG key from stable.repo.amd.com" >&2
                    return $rc 2>/dev/null || exit $rc
                }
                echo -e "X-Repo-Id: amdrocm-stable\nTypes: deb\nURIs: https://stable.repo.amd.com/\nSuites: noble\nComponents: main\nSigned-By: /etc/apt/keyrings/amdrocm.gpg" | $SUDO tee /etc/apt/sources.list.d/amdrocm-stable.sources > /dev/null
                $SUDO apt-get update
                $SUDO apt-get install -y --no-install-recommends \
                    amdrocm-core-dev10.0-gfx1151 hip-runtime-amd hipblas rocblas hipblaslt hsa-rocr \
                    rocprofiler-register rocsolver roctracer comgr
                # Export new ROCm 10.0 paths for this shell
                export ROCM_PATH=/opt/rocm/core-10.0
                export HIP_PATH="$ROCM_PATH"
                export PATH="$ROCM_PATH/bin:$ROCM_PATH/lib/llvm/bin:$PATH"
                export LD_LIBRARY_PATH="$ROCM_PATH/lib:${LD_LIBRARY_PATH:-}"
            elif command -v dnf >/dev/null 2>&1; then
                echo "🔧 Installing ROCm 10.0 runtime subset via dnf..."
                $SUDO dnf install -y "https://repo.radeon.com/amdgpu-install/10.0/rhel/9.5/amdgpu-install-10.0.0-1.el9.noarch.rpm"
                $SUDO dnf install -y rocm-dev hip-runtime-amd hipblas rocblas hipblaslt hsa-rocr
            else
                echo "❌ --install-rocm supports apt-get and dnf only." >&2
                echo "   See: https://rocm.docs.amd.com/en/latest/deploy/linux/install.html" >&2
                return $rc 2>/dev/null || exit $rc
            fi
            echo ""
            if check_rocm_runtime; then
                echo "✅ ROCm runtime installed successfully."
            else
                echo "❌ ROCm runtime still incomplete after install — reboot may be required" >&2
                echo "   for the amdgpu driver, or the install failed above." >&2
                return $rc 2>/dev/null || exit $rc
            fi
        else
            echo "Install ROCm 10.0 first (one-time setup) — or let us do it:"
            echo ""
            if command -v apt-get >/dev/null 2>&1; then
                echo "  Ubuntu 24.04 (ROCm 10.0 — stable repo):"
                echo "    sudo mkdir -p --mode=0755 /etc/apt/keyrings"
                echo "    wget https://stable.repo.amd.com/rocm/gpg/packages.gpg -O - | gpg --dearmor | sudo tee /etc/apt/keyrings/amdrocm.gpg > /dev/null"
                echo "    echo -e \"X-Repo-Id: amdrocm-stable\\nTypes: deb\\nURIs: https://stable.repo.amd.com/\\nSuites: noble\\nComponents: main\\nSigned-By: /etc/apt/keyrings/amdrocm.gpg\" | sudo tee /etc/apt/sources.list.d/amdrocm-stable.sources"
                echo "    sudo apt-get update && sudo apt-get install -y amdrocm-core-dev10.0-gfx1151 hip-runtime-amd hipblas rocblas hipblaslt hsa-rocr rocprofiler-register rocsolver roctracer comgr"
                echo "    export ROCM_PATH=/opt/rocm/core-10.0; export HIP_PATH=\$ROCM_PATH"
                echo ""
                echo "  One-command alternative:"
                echo "    source ./setup_env.sh --install-rocm"
                echo "  (Also supports ROCm 7.2.x — legacy repo.radeon.com/amdgpu-install/7.2.3)"
            elif command -v dnf >/dev/null 2>&1; then
                echo "  Fedora/RHEL (ROCm 10.0):"
                echo "    sudo dnf install https://repo.radeon.com/amdgpu-install/10.0/rhel/9.5/amdgpu-install-10.0.0-1.el9.noarch.rpm"
                echo "    sudo dnf install rocm-dev hip-runtime-amd hipblas rocblas hipblaslt hsa-rocr"
                echo ""
                echo "  One-command alternative:"
                echo "    source ./setup_env.sh --install-rocm"
            else
                echo "  See: https://rocm.docs.amd.com/en/latest/deploy/linux/install.html"
            fi
            echo ""
            echo "  Docker users: the Dockerfile installs ROCm automatically — just run docker compose up."
            echo ""
        fi
        # Stop launchers (fail fast) but don't kill an interactive shell sourcing this file
        return $rc 2>/dev/null || exit $rc
    fi
fi

echo "✅ Strix Halo ROCmFPX & Vulkan RADV environment successfully configured!"
echo "   • ROCm Target:        gfx1151 (Radeon 8060S 40 CU)"
echo "   • Vulkan ICD:         Mesa RADV (Wave64 + KHR_coopmat)"
echo "   • Unified Memory:     Enabled (128 GB LPDDR5X-8000)"
