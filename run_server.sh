#!/usr/bin/env bash
# ==============================================================================
# run_server.sh — High-Performance OpenAI-Compatible Server for Qwen 3.8 27B
# Auto-detects Vulkan0 (Mesa RADV Wave64) vs ROCm0 and sets safe reasoning budget
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/setup_env.sh"

# 1. Parse Arguments & Environment Overrides
MODEL_PATH="${MODEL_PATH:-}"
PORT="${PORT:-8000}"
HOST="${HOST:-0.0.0.0}"
CTX="${CTX:-262144}"
DRAFT_N="${DRAFT_N:-4}"
DRAFT_P="${DRAFT_P:-0.0}"
REASONING="${REASONING:-auto}"
REASONING_BUDGET="${REASONING_BUDGET:-4096}"
DEVICE="${DEVICE:-auto}"
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --ctx) CTX="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --draft-n) DRAFT_N="$2"; shift 2 ;;
        --draft-p) DRAFT_P="$2"; shift 2 ;;
        --reasoning) REASONING="$2"; shift 2 ;;
        --reasoning-budget) REASONING_BUDGET="$2"; shift 2 ;;
        --no-reasoning) REASONING="off"; shift ;;
        --strict) EXTRA_ARGS+=("--spec-mtp-strict-qwen"); shift ;;
        -*) EXTRA_ARGS+=("$1"); shift ;;
        *)
            if [ -z "$MODEL_PATH" ]; then
                MODEL_PATH="$1"
            else
                EXTRA_ARGS+=("$1")
            fi
            shift ;;
    esac
done

# 2. Resolve Model Path
if [ -z "$MODEL_PATH" ]; then
    if [ -f "${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf" ]; then
        MODEL_PATH="${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf"
    elif [ -f "${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP8.gguf" ]; then
        MODEL_PATH="${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP8.gguf"
    elif [ -f "${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP4-FAST.gguf" ]; then
        MODEL_PATH="${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP4-FAST.gguf"
    elif [ -f "/home/user/source/strix-halo-rocmfpx-hub/models/qwen38-27b/Qwen3.8-27B-ROCmFP4-FAST.gguf" ]; then
        MODEL_PATH="/home/user/source/strix-halo-rocmfpx-hub/models/qwen38-27b/Qwen3.8-27B-ROCmFP4-FAST.gguf"
    else
        MODEL_PATH="${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf"
    fi
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "⚠️  Model file not found at: $MODEL_PATH"
    echo "Please download the weights using:"
    echo "  ./download_model.sh"
    echo "or specify the path: ./run_server.sh /path/to/model.gguf"
    exit 1
fi

# 3. Locate llama-server Binary
LLAMA_SERVER_BIN="$(which llama-server 2>/dev/null || true)"
if [ -z "$LLAMA_SERVER_BIN" ] && [ -x "${SCRIPT_DIR}/engine/bin/llama-server" ]; then
    LLAMA_SERVER_BIN="${SCRIPT_DIR}/engine/bin/llama-server"
elif [ -z "$LLAMA_SERVER_BIN" ] && [ -x "/home/user/source/strix-halo-rocmfpx-hub/engine/bin/llama-server" ]; then
    LLAMA_SERVER_BIN="/home/user/source/strix-halo-rocmfpx-hub/engine/bin/llama-server"
fi

if [ ! -x "$LLAMA_SERVER_BIN" ]; then
    echo "❌ llama-server executable not found!"
    echo "Run ./build_engine.sh --prebuilt to get pre-compiled binaries."
    exit 1
fi

# 4. Device Auto-Detection (Vulkan0 vs ROCm0)
AVAILABLE_DEVICES="$("${LLAMA_SERVER_BIN}" --list-devices 2>/dev/null || true)"
if [ "$DEVICE" == "auto" ]; then
    if echo "$AVAILABLE_DEVICES" | grep -q "Vulkan0"; then
        DEVICE="Vulkan0"
    elif echo "$AVAILABLE_DEVICES" | grep -q "ROCm0"; then
        DEVICE="ROCm0"
        echo "⚠️  [NOTICE] 'Vulkan0' not found in engine build. Falling back to 'ROCm0'."
        echo "   MTP speculation will run at ~28 tok/s instead of 36 tok/s."
        echo "   👉 To enable Vulkan0 Wave64, download pre-built engine: ./build_engine.sh --prebuilt"
        echo "--------------------------------------------------------------------------------"
    else
        DEVICE="CPU"
        echo "⚠️  [WARN] No GPU backend found. Running on CPU."
    fi
fi

# 5. Build Command Line
CMD=(
    "${LLAMA_SERVER_BIN}"
    "-m" "${MODEL_PATH}"
    "-dev" "${DEVICE}"
    "-ngl" "99"
    "-fa" "on"
    "-np" "1"
    "-ctxcp" "0"
    "-cram" "16384"
    "-c" "${CTX}"
    "-b" "2048"
    "-ub" "1024"
    "-t" "16"
    "--poll" "100"
    "-ctk" "q8_0"
    "-ctv" "turbo4"
    "--presence-penalty" "1.5"
    "--repeat-penalty" "1.05"
    "--port" "${PORT}"
    "--host" "${HOST}"
    "--spec-type" "draft-mtp"
    "--spec-draft-n-max" "${DRAFT_N}"
    "--spec-draft-p-min" "${DRAFT_P}"
)

if [ "$REASONING" == "off" ]; then
    CMD+=("--reasoning" "off")
elif [ -n "$REASONING_BUDGET" ] && [ "$REASONING_BUDGET" -ge 0 ]; then
    CMD+=("--reasoning-budget" "${REASONING_BUDGET}")
fi

if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    CMD+=("${EXTRA_ARGS[@]}")
fi

echo "================================================================================"
echo " 🚀 Starting Qwen 3.8 27B Server on AMD Strix Halo"
echo "================================================================================"
echo " Model:          $(basename "$MODEL_PATH")"
echo " Device Backend: ${DEVICE}"
echo " Context:        ${CTX} tokens (TurboQuant KV: K=q8_0, V=turbo4)"
echo " Speculation:    MTP Speculative Decoding (n_max=${DRAFT_N}, p_min=${DRAFT_P})"
echo " Reasoning:      ${REASONING} (Budget: ${REASONING_BUDGET:-unlimited} tokens)"
echo " API Endpoint:   http://${HOST}:${PORT}/v1"
echo "================================================================================"

exec "${CMD[@]}"
