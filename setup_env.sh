#!/usr/bin/env bash
# ==============================================================================
# setup_env.sh — Strix Halo (Ryzen AI Max+ 395 / Radeon 8060S / gfx1151)
# Environment Setup for ROCmFPX & Vulkan RADV Wave64 Co-op Matrix Acceleration
# ==============================================================================

export HSA_OVERRIDE_GFX_VERSION=11.5.1
export GGML_HIP_ENABLE_UNIFIED_MEMORY=1
export HIP_VISIBLE_DEVICES=0
export ROCM_FLUSH_ACCEPT=1

export AMD_VULKAN_ICD=RADV
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
export RADV_PERFTEST="gpl,sam,nggc"

# Find local engine if available
if [ -d "/home/user/source/strix-halo-rocmfpx-hub/engine/bin" ]; then
    export PATH="/home/user/source/strix-halo-rocmfpx-hub/engine/bin:${PATH}"
    export LD_LIBRARY_PATH="/home/user/source/strix-halo-rocmfpx-hub/engine/bin:${LD_LIBRARY_PATH:-}"
fi

echo "✅ Strix Halo ROCmFPX & Vulkan RADV environment successfully configured!"
echo "   • ROCm Target:        gfx1151 (Radeon 8060S 40 CU)"
echo "   • Vulkan ICD:         Mesa RADV (Wave64 + KHR_coopmat)"
echo "   • Unified Memory:     Enabled (128 GB LPDDR5X-8000)"
