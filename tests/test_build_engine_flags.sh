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

printf '%s\n' "build_engine portability flag tests passed"
