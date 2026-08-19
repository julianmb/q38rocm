#!/usr/bin/env bash
# ==============================================================================
# run_inference.sh — Strix Halo Unified Memory Inference Runner
# ==============================================================================
# Usage: ./scripts/run_inference.sh [cli|server] [speed|quality] /path/to/model.gguf
# Env:   CTX_SIZE (default: cli=8192, server=131072)
set -euo pipefail

MODE="${1:-cli}"
VARIANT="${2:-speed}"
MODEL_PATH="${3:-}"

if [ -z "$MODEL_PATH" ]; then
    # Default fallbacks if no model path is passed
    if [ "$VARIANT" == "speed" ]; then
        MODEL_PATH="Ornith-1.0-35B-ROCmFPX-Speed-StrixHalo.gguf"
    else
        MODEL_PATH="Ornith-1.0-35B-ROCmFPX-Quality-StrixHalo.gguf"
    fi
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Model file ($MODEL_PATH) not found."
    echo "Usage: $0 [cli|server] [speed|quality] /path/to/model.gguf"
    exit 1
fi

BIN_DIR="ROCmFPX/build-strix-rocmfp4/bin"
if [ ! -d "$BIN_DIR" ]; then
    echo "Error: ROCmFPX binaries not found. Please run ./scripts/build_rocmfpx.sh first."
    exit 1
fi

# Required environment variables for AMD Strix Halo / gfx1151
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export GGML_HIP_ENABLE_UNIFIED_MEMORY=1

# Context size handling
if [ -z "${CTX_SIZE:-}" ]; then
    if [ "$MODE" == "server" ]; then
        CTX_SIZE=131072
    else
        CTX_SIZE=8192
    fi
fi

echo "=========================================================="
echo " Launching ROCmFPX Inference on Strix Halo (gfx1151)"
echo " Mode: $MODE | Variant: $VARIANT | Context: $CTX_SIZE"
echo " Model: $MODEL_PATH"
echo "=========================================================="

COMMON_ARGS=(
    -m "$MODEL_PATH"
    -dev ROCm0 -ngl 999 -fa on
    -c "$CTX_SIZE" -ctk q8_0 -ctv q8_0
    -b 512 -ub 512 --jinja
)

shift 3 || true
EXTRA_ARGS=("$@")

if [ "$MODE" == "cli" ]; then
    exec "$BIN_DIR/llama-cli" "${COMMON_ARGS[@]}" -i "${EXTRA_ARGS[@]}"
elif [ "$MODE" == "server" ]; then
    echo "Starting OpenAI-compatible server at http://127.0.0.1:8080"
    exec "$BIN_DIR/llama-server" "${COMMON_ARGS[@]}" \
        --host 127.0.0.1 --port 8080 "${EXTRA_ARGS[@]}"
else
    echo "Error: Unknown mode '$MODE'. Use 'cli' or 'server'."
    exit 1
fi
