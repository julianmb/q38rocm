#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$(<"$ROOT_DIR/build_engine.sh")"

[[ "$script" == *"-DCMAKE_POSITION_INDEPENDENT_CODE=ON"* ]]
[[ "$script" == *"-DLLAMA_BUILD_WEBUI="* ]]
[[ "$script" == *"BUILD_WEBUI=0"* ]]
[[ "$script" == *"--webui) BUILD_WEBUI=1"* ]]
[[ "$script" == *"--rocm-only|--no-vulkan) ENABLE_VULKAN=0"* ]]
[[ "$script" == *"sudo apt install spirv-headers"* ]]
[[ "$script" == *"-DGGML_VULKAN=OFF"* ]]

# Release asset pinning (issue #20): RELEASE_TARBALL_URL and EXPECTED_TARBALL_SHA
# must be bumped together. The checksum kept pointing at the v1.5.0 asset while the
# URL served v1.5.2, which made `./build_engine.sh --prebuilt` fail for every user.
engine_url="$(grep -m1 '^RELEASE_TARBALL_URL=' "$ROOT_DIR/build_engine.sh")"
engine_sha="$(grep -m1 '^EXPECTED_TARBALL_SHA=' "$ROOT_DIR/build_engine.sh")"
dockerfile_url="$(grep -m1 'releases/download/' "$ROOT_DIR/Dockerfile")"

[[ "$engine_sha" =~ ^EXPECTED_TARBALL_SHA=\"[0-9a-f]{64}\"$ ]]
engine_tag="${engine_url##*/v}"
engine_tag="${engine_tag%%/*}"
[[ "$engine_tag" == [0-9]* ]]
[[ "$engine_url"  == *"/releases/download/v${engine_tag}/strix-halo-rocmfpx-engine-v${engine_tag}-linux-x86_64.tar.gz\""* ]]
[[ "$dockerfile_url" == *"/releases/download/v${engine_tag}/"* ]]

printf '%s\n' "build_engine portability flag tests passed"
