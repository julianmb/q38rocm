#!/usr/bin/env bash
# ==============================================================================
# build_engine.sh — Build ROCmFPX Engine (llama.cpp fork) for AMD Strix Halo (gfx1151)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="${SCRIPT_DIR}/engine"
REPO_URL="https://github.com/charlie12345/ROCmFPX.git"
PINNED_COMMIT="e87d53e"

echo "================================================================================"
echo " ⚙️ Building ROCmFPX llama.cpp Engine for AMD Strix Halo"
echo " Target Architecture: gfx1151 (Radeon 8060S / RDNA 3.5)"
echo " Required Drivers: Mesa RADV (Vulkan) + ROCm / HIP 7.x"
echo "================================================================================"

# 1. Dependency Checks
for tool in cmake git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Error: '$tool' is required but not installed."
        exit 1
    fi
done

# 2. Clone or Update ROCmFPX Repository
if [ ! -d "${ENGINE_DIR}/src/.git" ]; then
    echo "Cloning ROCmFPX toolchain into ${ENGINE_DIR}/src..."
    mkdir -p "${ENGINE_DIR}"
    git clone "${REPO_URL}" "${ENGINE_DIR}/src"
fi

cd "${ENGINE_DIR}/src"
echo "Checking out pinned commit: ${PINNED_COMMIT}..."
git fetch origin
git checkout "${PINNED_COMMIT}" || true

# 3. Configure CMake with Dual ROCm + Vulkan Acceleration
BUILD_DIR="${ENGINE_DIR}/src/build"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

CMAKE_FLAGS=(
    -DGGML_HIP=ON
    -DAMDGPU_TARGETS=gfx1151
    -DGGML_VULKAN=ON
    -DGGML_VULKAN_CHECK_RESULTS=OFF
    -DGGML_AVX=ON
    -DGGML_AVX2=ON
    -DGGML_AVX512=ON
    -DGGML_F16C=ON
    -DGGML_FMA=ON
    -DCMAKE_BUILD_TYPE=Release
)

echo "Configuring CMake with Vulkan & ROCm support..."
cmake .. "${CMAKE_FLAGS[@]}"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"
echo "Compiling binaries with ${JOBS} parallel threads..."
cmake --build . --config Release -j "${JOBS}" --target llama-server llama-cli llama-bench llama-quantize

# 4. Link/Install Executables to engine/bin
mkdir -p "${ENGINE_DIR}/bin"
cp -f bin/llama-server bin/llama-cli bin/llama-bench bin/llama-quantize "${ENGINE_DIR}/bin/"
if [ -d bin ]; then
    cp -f bin/*.so* "${ENGINE_DIR}/bin/" 2>/dev/null || true
fi

echo "================================================================================"
echo " ✅ Build Complete!"
echo " Binaries installed to: ${ENGINE_DIR}/bin"
echo " Export environment:    source ./setup_env.sh"
echo "================================================================================"
