#!/usr/bin/env bash
# ==============================================================================
# build_engine.sh — Build or Download ROCmFPX Engine for AMD Strix Halo (gfx1151)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="${SCRIPT_DIR}/engine"
REPO_URL="https://github.com/charlie12345/ROCmFPX.git"
PINNED_COMMIT="${PINNED_COMMIT:-0fc9568e07ccc8553010864cb8db1957e629cbfa}"
RELEASE_TARBALL_URL="https://github.com/julianmb/q38rocm/releases/download/v1.5.3/strix-halo-rocmfpx-engine-v1.5.3-linux-x86_64.tar.gz"
EXPECTED_TARBALL_SHA="10f060aa19ce9976f8807ecdacda8f708a13209cad0aa7c3111293ebe0ca5ad7"
# what `llama-server --version` reports for the pinned prebuilt. Warns when the
# installed binary does not match the release we think we installed (issues
# #20/#21 both stalled because a binary could not be mapped to a revision).
PREBUILT_ENGINE_BUILD="${PREBUILT_ENGINE_BUILD:-version: 244 (0fc9568)}"
LINKAGE="static"
CLEAN_BUILD=0
USE_PREBUILT=0
ENABLE_VULKAN=1
BUILD_WEBUI=0

# record where the engine on disk came from, so a bug report can say which
# source revision it is actually running (see issues #20/#21)
write_build_info() {
    local origin="$1"
    local engine_build="$2"
    mkdir -p "${ENGINE_DIR}"
    {
        echo "origin:         ${origin}"
        echo "generated:      $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "engine build:   ${engine_build}"
        if [ "${origin}" = "prebuilt" ]; then
            echo "release url:    ${RELEASE_TARBALL_URL}"
            echo "tarball sha256: ${EXPECTED_TARBALL_SHA}"
        else
            echo "pinned commit:  ${PINNED_COMMIT}"
            echo "patches:        $(cd "${SCRIPT_DIR}/patches" 2>/dev/null && ls *.patch 2>/dev/null | tr '\n' ' ')"
        fi
        echo "binary sha256:  $(sha256sum "${ENGINE_DIR}/bin/llama-server" 2>/dev/null | cut -d' ' -f1)"
    } > "${ENGINE_DIR}/BUILD_INFO.txt"
    echo "Provenance:     ${ENGINE_DIR}/BUILD_INFO.txt"
}

# Print the engine build and, when we know what to expect (prebuilt only), warn on a
# mismatch. Source builds legitimately report the pinned commit instead, so they pass
# an empty expectation rather than tripping the check.
report_engine_build() {
    local engine_build="$1"
    local expected="$2"
    echo "Engine build:   ${engine_build}"
    if [ -z "${engine_build}" ]; then
        echo "⚠️  llama-server reported no build string — check the install" >&2
        return
    fi
    if [ -n "${expected}" ] && [[ "${engine_build}" != *"${expected}"* ]]; then
        echo "⚠️  Expected '${expected}' in the build string, got '${engine_build}'" >&2
        echo "   Update PREBUILT_ENGINE_BUILD after re-releasing, otherwise bug reports" >&2
        echo "   will not match the provenance recorded in engine/BUILD_INFO.txt." >&2
    fi
}

show_status() {
    echo "Pinned commit:             ${PINNED_COMMIT}"
    echo "Expected prebuilt build:   ${PREBUILT_ENGINE_BUILD}"
    echo "Applied patches:"
    local patch_found=0
    local patch_file
    for patch_file in "${SCRIPT_DIR}/patches/"*.patch; do
        if [ -f "${patch_file}" ]; then
            echo "  - $(basename "${patch_file}")"
            patch_found=1
        fi
    done
    if [ "${patch_found}" -eq 0 ]; then
        echo "  (none)"
    fi

    echo "BUILD_INFO.txt:"
    if [ -f "${ENGINE_DIR}/BUILD_INFO.txt" ]; then
        cat "${ENGINE_DIR}/BUILD_INFO.txt"
    else
        echo "  (not present)"
    fi

    echo "llama-server --version:"
    if [ -x "${ENGINE_DIR}/bin/llama-server" ]; then
        "${ENGINE_DIR}/bin/llama-server" --version 2>&1 || true
    else
        echo "  (not present)"
    fi
}

download_prebuilt() {
    echo "================================================================================"
    echo " 📥 Downloading Pre-Compiled ROCmFPX Engine (v1.5.3) for AMD Strix Halo"
    echo " Source: ${RELEASE_TARBALL_URL}"
    echo "================================================================================"
    mkdir -p "${ENGINE_DIR}"
    TAR_PATH="/tmp/strix-halo-engine-v1.5.3.tar.gz"
    
    curl -L "${RELEASE_TARBALL_URL}" -o "${TAR_PATH}" --progress-bar
    
    if command -v sha256sum >/dev/null 2>&1; then
        if ! echo "${EXPECTED_TARBALL_SHA}  ${TAR_PATH}" | sha256sum -c -; then
            echo "❌ Checksum mismatch for $(basename "${TAR_PATH}")" >&2
            echo "   expected: ${EXPECTED_TARBALL_SHA}" >&2
            echo "   actual:   $(sha256sum "${TAR_PATH}" | cut -d' ' -f1)" >&2
            echo "   The published asset does not match the pinned digest (see issue #20)." >&2
            echo "   Either update EXPECTED_TARBALL_SHA after verifying the new digest, or" >&2
            echo "   re-pin RELEASE_TARBALL_URL to a known-good release." >&2
            exit 1
        fi
        echo "✅ Checksum verified!"
    fi
    
    echo "Extracting binaries into ${ENGINE_DIR}..."
    tar -xzf "${TAR_PATH}" -C /tmp/
    # never write through a symlinked engine/bin: it may point at the shared
    # canonical ROCmFPX build, and polluting it would break every other project
    if [ -L "${ENGINE_DIR}/bin" ]; then
        rm "${ENGINE_DIR}/bin"
    fi
    cp -a /tmp/strix-halo-rocmfpx-engine/* "${ENGINE_DIR}/"
    rm -rf /tmp/strix-halo-rocmfpx-engine "${TAR_PATH}"
    
    # v1.5.1 shipped llama-server at the archive root instead of bin/, which silently
    # produced an engine/bin without a server binary
    if [ ! -x "${ENGINE_DIR}/bin/llama-server" ]; then
        echo "❌ No llama-server in ${ENGINE_DIR}/bin after extraction" >&2
        echo "   The release tarball layout is unexpected; list it with:" >&2
        echo "     tar -tzf ${TAR_PATH} | head" >&2
        exit 1
    fi

    echo "✅ Pre-built engine ready in: ${ENGINE_DIR}/bin"
    local engine_build
    engine_build="$("${ENGINE_DIR}/bin/llama-server" --version 2>&1 | head -1)"
    report_engine_build "${engine_build}" "${PREBUILT_ENGINE_BUILD}"
    write_build_info "prebuilt" "${engine_build}"
    echo "Verifying available hardware acceleration backends..."
    "${ENGINE_DIR}/bin/llama-server" --list-devices 2>/dev/null || true
    echo "Run: source ./setup_env.sh"
    exit 0
}

# Parse build mode before dependency checks.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --status) show_status; exit 0 ;;
        --prebuilt|--download) USE_PREBUILT=1; shift ;;
        --static) LINKAGE="static"; shift ;;
        --shared) LINKAGE="shared"; shift ;;
        --clean) CLEAN_BUILD=1; shift ;;
        --webui) BUILD_WEBUI=1; shift ;;
        --rocm-only|--no-vulkan) ENABLE_VULKAN=0; shift ;;
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
echo " Vulkan:          $([ "$ENABLE_VULKAN" -eq 1 ] && echo enabled || echo disabled)"
echo " WebUI:           $([ "$BUILD_WEBUI" -eq 1 ] && echo enabled || echo disabled)"
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

# Check Vulkan build dependencies when the dual-backend build is requested.
if [ "$ENABLE_VULKAN" -eq 1 ] && ! command -v glslc >/dev/null 2>&1; then
    echo "⚠️  'glslc' (Vulkan shader compiler) not found."
    echo "   Without glslc, CMake will produce a ROCm-only binary without Vulkan0 Wave64 support."
    echo "   To compile with Vulkan, install: sudo apt install glslc libvulkan-dev mesa-vulkan-drivers spirv-headers"
    echo "   Or explicitly build HIP-only: ./build_engine.sh --rocm-only"
    read -p "Would you like to download the pre-compiled Strix Halo binaries instead? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        download_prebuilt
    fi
fi

if [ "$ENABLE_VULKAN" -eq 1 ]; then
    SPIRV_HEADER_FOUND=0
    for header in \
        /usr/include/spirv/unified1/spirv.hpp \
        /usr/local/include/spirv/unified1/spirv.hpp \
        /usr/include/spirv-headers/spirv.hpp \
        /usr/local/include/spirv-headers/spirv.hpp; do
        if [ -f "$header" ]; then
            SPIRV_HEADER_FOUND=1
            break
        fi
    done
    if [ "$SPIRV_HEADER_FOUND" -ne 1 ]; then
        echo "❌ SPIR-V C++ headers are required for the Vulkan backend (issue #9)." >&2
        echo "   Ubuntu 24.04: sudo apt install spirv-headers" >&2
        echo "   Or build HIP-only: ./build_engine.sh --rocm-only" >&2
        exit 1
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

shopt -s nullglob
for PATCH_FILE in "${SCRIPT_DIR}/patches/"*.patch; do
    if git apply --check "${PATCH_FILE}" 2>/dev/null; then
        echo "Applying $(basename "${PATCH_FILE}")..."
        git apply "${PATCH_FILE}"
    elif git apply --reverse --check "${PATCH_FILE}" 2>/dev/null; then
        # the source tree already carries this patch (e.g. a previous build left it
        # applied, or it was applied by hand) — re-applying would fail the build
        echo "Already applied: $(basename "${PATCH_FILE}")"
    else
        echo "❌ Local patch does not apply at ${PINNED_COMMIT}: ${PATCH_FILE}" >&2
        echo "   Rebase it, or restore the pristine source with:" >&2
        echo "     git -C ${ENGINE_DIR}/src checkout -- ." >&2
        exit 1
    fi
done

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
    -DGGML_VULKAN_CHECK_RESULTS=OFF
    -DGGML_AVX=ON
    -DGGML_AVX2=ON
    -DGGML_AVX512=ON
    -DGGML_F16C=ON
    -DGGML_FMA=ON
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DLLAMA_BUILD_WEBUI=$([ "$BUILD_WEBUI" -eq 1 ] && echo ON || echo OFF)
    -DCMAKE_BUILD_TYPE=Release
)

if [ "$ENABLE_VULKAN" -eq 1 ]; then
    CMAKE_FLAGS+=("-DGGML_VULKAN=ON")
else
    CMAKE_FLAGS+=("-DGGML_VULKAN=OFF")
fi

if [ "$LINKAGE" = "static" ]; then
    CMAKE_FLAGS+=("-DGGML_BACKEND_DL=OFF" "-DBUILD_SHARED_LIBS=OFF")
else
    CMAKE_FLAGS+=("-DGGML_BACKEND_DL=OFF" "-DBUILD_SHARED_LIBS=ON")
fi

if [ "$ENABLE_VULKAN" -eq 1 ]; then
    echo "Configuring a native ${LINKAGE} build with Vulkan & ROCm support..."
else
    echo "Configuring a native ${LINKAGE} ROCm/HIP-only build..."
fi
cmake -S "${ENGINE_DIR}/src" -B "${BUILD_DIR}" "${CMAKE_FLAGS[@]}"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"
echo "Compiling binaries with ${JOBS} parallel threads..."
cmake --build . --config Release -j "${JOBS}" --target llama-server llama-cli llama-bench llama-quantize

# Link/Install Executables to engine/bin
# same symlink guard as download_prebuilt: never write through engine/bin
if [ -L "${ENGINE_DIR}/bin" ]; then
    rm "${ENGINE_DIR}/bin"
fi
mkdir -p "${ENGINE_DIR}/bin"
cp -f bin/llama-server bin/llama-cli bin/llama-bench bin/llama-quantize "${ENGINE_DIR}/bin/"
if [ "$LINKAGE" = "shared" ] && [ -d bin ]; then
    # shared builds need their .so files; copying them into a static deployment
    # makes the static binary dlopen stale libs at startup and abort
    cp -f bin/*.so* "${ENGINE_DIR}/bin/" 2>/dev/null || true
fi

engine_build="$("${ENGINE_DIR}/bin/llama-server" --version 2>&1 | head -1)"
report_engine_build "${engine_build}" ""
write_build_info "source" "${engine_build}"

echo "================================================================================"
echo " ✅ Build Complete!"
echo " Binaries installed to: ${ENGINE_DIR}/bin"
echo " Detected backends on host:"
"${ENGINE_DIR}/bin/llama-server" --list-devices 2>/dev/null || true
echo " Export environment:    source ./setup_env.sh"
echo "================================================================================"
