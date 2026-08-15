#!/usr/bin/env bash
# ==============================================================================
# run_server.sh — High-Performance OpenAI-Compatible Server for Qwen 3.8 27B ROCmFP4_FAST
# Optimized for AMD Strix Halo (Ryzen AI Max+ 395 / Radeon 8060S / Mesa RADV Wave64)
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/setup_env.sh"

# Resolve model path
if [ -n "$1" ]; then
    MODEL_PATH="$1"
elif [ -n "${MODEL_PATH:-}" ]; then
    MODEL_PATH="${MODEL_PATH}"
elif [ -f "${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf" ]; then
    MODEL_PATH="${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf"
elif [ -f "${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP4-FAST.gguf" ]; then
    MODEL_PATH="${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP4-FAST.gguf"
elif [ -f "/home/user/source/strix-halo-rocmfpx-hub/models/qwen38-27b/Qwen3.8-27B-ROCmFP4-FAST.gguf" ]; then
    MODEL_PATH="/home/user/source/strix-halo-rocmfpx-hub/models/qwen38-27b/Qwen3.8-27B-ROCmFP4-FAST.gguf"
else
    MODEL_PATH="${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf"
fi

PORT="${PORT:-8000}"
HOST="${HOST:-0.0.0.0}"
CTX="${CTX:-32768}"
DRAFT_N="${DRAFT_N:-6}"
DRAFT_P="${DRAFT_P:-0.60}"

if [ ! -f "$MODEL_PATH" ]; then
    echo "⚠️  Model file not found at: $MODEL_PATH"
    echo "Please download the weights using:"
    echo "  ./download_model.sh"
    echo "or specify the path as first argument: ./run_server.sh /path/to/Qwen3.8-27B-ROCmFP4-FAST.gguf"
    exit 1
fi

LLAMA_SERVER_BIN="$(which llama-server 2>/dev/null || true)"
if [ -z "$LLAMA_SERVER_BIN" ] && [ -x "${SCRIPT_DIR}/engine/bin/llama-server" ]; then
    LLAMA_SERVER_BIN="${SCRIPT_DIR}/engine/bin/llama-server"
elif [ -z "$LLAMA_SERVER_BIN" ] && [ -x "/home/user/source/strix-halo-rocmfpx-hub/engine/bin/llama-server" ]; then
    LLAMA_SERVER_BIN="/home/user/source/strix-halo-rocmfpx-hub/engine/bin/llama-server"
fi

if [ ! -x "$LLAMA_SERVER_BIN" ]; then
    echo "❌ llama-server executable not found!"
    exit 1
fi

echo "================================================================================"
echo " 🚀 Starting Qwen 3.8 27B ROCmFP4_FAST OpenAI Server on AMD Strix Halo"
echo "================================================================================"
echo " Model:          ${MODEL_PATH}"
echo " Backend:        Vulkan0 (Mesa RADV STRIX_HALO Wave64 KHR_coopmat)"
echo " Context:        ${CTX} tokens"
echo " Speculation:    MTP Speculative Decoding (n_max=${DRAFT_N}, p_min=${DRAFT_P})"
echo " KV Cache:       Asymmetric TurboQuant (K=q8_0, V=turbo4)"
echo " API Endpoint:   http://${HOST}:${PORT}/v1"
echo "================================================================================"

exec "${LLAMA_SERVER_BIN}" \
    -m "${MODEL_PATH}" \
    -dev Vulkan0 \
    -ngl 99 \
    -fa on \
    -np 1 \
    -ctxcp 0 \
    -cram 16384 \
    -c "${CTX}" \
    -b 2048 \
    -ub 1024 \
    -t 16 \
    --poll 100 \
    -ctk q8_0 \
    -ctv turbo4 \
    --port "${PORT}" \
    --host "${HOST}" \
    --spec-type draft-mtp \
    --spec-draft-n-max "${DRAFT_N}" \
    --spec-draft-p-min "${DRAFT_P}"
