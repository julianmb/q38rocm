#!/usr/bin/env bash
# ==============================================================================
# build_rocmfpx.sh — Legacy wrapper (use ./build_engine.sh instead)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "⚠️  scripts/build_rocmfpx.sh is deprecated — delegating to ./build_engine.sh" >&2
echo "   The pinned commit and patches are managed in build_engine.sh; direct" >&2
echo "   ROCmFPX clones should use: git clone https://github.com/charlie12345/ROCmFPX.git" >&2
exec "${SCRIPT_DIR}/build_engine.sh" "$@"
