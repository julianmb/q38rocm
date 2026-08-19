#!/usr/bin/env bash
# ==============================================================================
# build_engine.sh — Build or Download ROCmFPX Engine for AMD Strix Halo (gfx1151)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="${SCRIPT_DIR}/engine"
REPO_URL="https://github.com/charlie12345/ROCmFPX.git"
PINNED_COMMIT="${PINNED_COMMIT:-0fc9568e07ccc8553010864cb8db1957e629cbfa}"
RELEASE_TARBALL_URL="https://github.com/julianmb/q38rocm/releases/download/v1.0.0/strix-halo-rocmfpx-engine-v1.0.0-linux-x86_64.tar.gz"
EXPECTED_TARBALL_SHA="bbc7845db0c012b97f1c9b8a2733a7083c6f9a749a453866fbe1994151d3364f"
LINKAGE="static"
CLEAN_BUILD=0
USE_PREBUILT=0

download_prebuilt() {
    echo "================================================================================"
    echo " 📥 Downloading Pre-Compiled ROCmFPX Engine (v1.0.0) for AMD Strix Halo"
    echo " Source: ${RELEASE_TARBALL_URL}"
    echo "================================================================================"
    mkdir -p "${ENGINE_DIR}"
    TAR_PATH="/tmp/strix-halo-engine-v1.0.0.tar.gz"
    
    curl -L "${RELEASE_TARBALL_URL}" -o "${TAR_PATH}" --progress-bar
    
    if command -v sha256sum >/dev/null 2>&1; then
        echo "${EXPECTED_TARBALL_SHA}  ${TAR_PATH}" | sha256sum -c -
        echo "✅ Checksum verified!"
    fi
    
    echo "Extracting binaries into ${ENGINE_DIR}..."
    tar -xzf "${TAR_PATH}" -C /tmp/
    cp -a /tmp/strix-halo-rocmfpx-engine/* "${ENGINE_DIR}/"
    rm -rf /tmp/strix-halo-rocmfpx-engine "${TAR_PATH}"
    
    echo "✅ Pre-built engine ready in: ${ENGINE_DIR}/bin"
    echo "Verifying available hardware acceleration backends..."
    "${ENGINE_DIR}/bin/llama-server" --list-devices 2>/dev/null || true
    echo "Run: source ./setup_env.sh"
    exit 0
}

# Parse build mode before dependency checks.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prebuilt|--download) USE_PREBUILT=1; shift ;;
        --static) LINKAGE="static"; shift ;;
        --shared) LINKAGE="shared"; shift ;;
        --clean) CLEAN_BUILD=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ "$USE_PREBUILT" -eq 1 ]; then
    download_prebuilt
fi

echo "================================================================================"
echo " ⚙️ ROCmFPX llama.cpp Engine Setup for AMD Strix Halo"
echo " Target Architecture: gfx1151 (Radeon 8060S / RDNA 3.5)"
echo " Source Revision: ${PINNED_COMMIT}"
echo " Linkage:         ${LINKAGE}"
echo " Options: Run './build_engine.sh --prebuilt' to download pre-compiled binaries"
echo "================================================================================"

# Check compiler dependencies
MISSING_TOOLS=0
for tool in cmake git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "⚠️  Tool '$tool' is not installed."
        MISSING_TOOLS=1
    fi
done

# Check Vulkan shader compiler (glslc)
if ! command -v glslc >/dev/null 2>&1; then
    echo "⚠️  'glslc' (Vulkan shader compiler) not found."
    echo "   Without glslc, CMake will produce a ROCm-only binary without Vulkan0 Wave64 support."
    echo "   To compile with Vulkan, install: sudo apt install glslc libvulkan-dev mesa-vulkan-drivers"
    read -p "Would you like to download the pre-compiled Strix Halo binaries instead? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        download_prebuilt
    fi
fi

if [ "$MISSING_TOOLS" -eq 1 ]; then
    echo "Build tools are missing. Falling back to pre-compiled release download..."
    download_prebuilt
fi

# Clone or Update ROCmFPX Repository
if [ ! -d "${ENGINE_DIR}/src/.git" ]; then
    echo "Cloning ROCmFPX toolchain into ${ENGINE_DIR}/src..."
    mkdir -p "${ENGINE_DIR}"
    git clone "${REPO_URL}" "${ENGINE_DIR}/src"
fi

cd "${ENGINE_DIR}/src"
echo "Checking out pinned commit: ${PINNED_COMMIT}..."
git fetch origin
git checkout --detach "${PINNED_COMMIT}"

# Configure CMake with Dual ROCm + Vulkan Acceleration
BUILD_DIR="${ENGINE_DIR}/src/build-${LINKAGE}"
if [ "$CLEAN_BUILD" -eq 1 ] && [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
fi
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

CMAKE_FLAGS=(
    -DGGML_NATIVE=ON
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

if [ "$LINKAGE" = "static" ]; then
    CMAKE_FLAGS+=("-DGGML_BACKEND_DL=OFF" "-DBUILD_SHARED_LIBS=OFF")
else
    CMAKE_FLAGS+=("-DGGML_BACKEND_DL=OFF" "-DBUILD_SHARED_LIBS=ON")
fi

echo "Configuring a native ${LINKAGE} build with Vulkan & ROCm support..."
cmake -S "${ENGINE_DIR}/src" -B "${BUILD_DIR}" "${CMAKE_FLAGS[@]}"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"
echo "Compiling binaries with ${JOBS} parallel threads..."
cmake --build . --config Release -j "${JOBS}" --target llama-server llama-cli llama-bench llama-quantize

# Link/Install Executables to engine/bin
mkdir -p "${ENGINE_DIR}/bin"
cp -f bin/llama-server bin/llama-cli bin/llama-bench bin/llama-quantize "${ENGINE_DIR}/bin/"
if [ -d bin ]; then
    cp -f bin/*.so* "${ENGINE_DIR}/bin/" 2>/dev/null || true
fi

echo "================================================================================"
echo " ✅ Build Complete!"
echo " Binaries installed to: ${ENGINE_DIR}/bin"
echo " Detected backends on host:"
"${ENGINE_DIR}/bin/llama-server" --list-devices 2>/dev/null || true
echo " Export environment:    source ./setup_env.sh"
echo "================================================================================"
