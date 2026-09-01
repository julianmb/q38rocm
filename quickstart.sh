#!/usr/bin/env bash
# ==============================================================================
# quickstart.sh — 1-Command Interactive Launcher for Qwen 3.8 27B on AMD Strix Halo
# Automatically verifies environment, boots background server, and opens chat TUI
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

source "${SCRIPT_DIR}/setup_env.sh"
source "${SCRIPT_DIR}/scripts/cache_profile.sh"

PORT="${PORT:-8000}"
HOST="127.0.0.1"
REASONING="${REASONING:-auto}"
REASONING_BUDGET="${REASONING_BUDGET:-4096}"
HUB_DIR="${HALOFPX_HUB_DIR:-${HOME}/source/halofpx-research}"
MODEL_FILE="${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP4-FAST.gguf"
LEGACY_MODEL="${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf"
FALLBACK_MODEL="${HUB_DIR}/models/qwen38-27b/Qwen3.8-27B-ROCmFP4-FAST.gguf"
CACHE_MODE="${CACHE_MODE:-speed}"
configure_cache_profile
if [ "${CACHE_MODE}" = "cache" ]; then
    mkdir -p "${SLOT_SAVE_PATH}"
fi

echo "================================================================================"
echo " 🚀 Qwen 3.8 27B ROCmFP4_FAST — Strix Halo 1-Command Quickstart"
echo "================================================================================"

# 1. Check Model Weights
if [ ! -f "$MODEL_FILE" ] && [ -f "$LEGACY_MODEL" ]; then
    MODEL_FILE="$LEGACY_MODEL"
elif [ ! -f "$MODEL_FILE" ] && [ -f "$FALLBACK_MODEL" ]; then
    MODEL_FILE="$FALLBACK_MODEL"
fi

if [ ! -f "$MODEL_FILE" ]; then
    echo "⚠️  Model weights not found locally."
    read -p "Would you like to download Qwen3.8-27B-ROCmFP4-FAST.gguf now from Hugging Face? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Download cancelled. Please run ./download_model.sh when ready."
        exit 1
    fi
    ./download_model.sh
fi

# 2. Locate llama-server
LLAMA_SERVER_BIN="$(which llama-server 2>/dev/null || true)"
if [ -z "$LLAMA_SERVER_BIN" ] && [ -x "${SCRIPT_DIR}/engine/bin/llama-server" ]; then
    LLAMA_SERVER_BIN="${SCRIPT_DIR}/engine/bin/llama-server"
elif [ -z "$LLAMA_SERVER_BIN" ] && [ -x "${HUB_DIR}/engine/bin/llama-server" ]; then
    LLAMA_SERVER_BIN="${HUB_DIR}/engine/bin/llama-server"
fi

if [ -z "$LLAMA_SERVER_BIN" ]; then
    echo "❌ Error: llama-server executable not found!"
    echo "Downloading pre-compiled Strix Halo binaries..."
    ./build_engine.sh --prebuilt
    LLAMA_SERVER_BIN="${SCRIPT_DIR}/engine/bin/llama-server"
fi

# 3. Device Detection
AVAILABLE_DEVICES="$("${LLAMA_SERVER_BIN}" --list-devices 2>/dev/null || true)"
if echo "$AVAILABLE_DEVICES" | grep -q "Vulkan0"; then
    DEVICE="Vulkan0"
elif echo "$AVAILABLE_DEVICES" | grep -q "ROCm0"; then
    DEVICE="ROCm0"
    echo "⚠️  [NOTICE] Vulkan0 not present in current binary. Using ROCm0 (~28 tok/s)."
else
    DEVICE="CPU"
fi

# 4. Check If Port is Already Active
if curl -s "http://${HOST}:${PORT}/health" 2>/dev/null | grep -q "ok"; then
    echo "✅ Server already running on port ${PORT}!"
    echo "Attaching streaming chat interface..."
    python3 "${SCRIPT_DIR}/scripts/chat_tui.py" --port "${PORT}"
    exit 0
fi

# 5. Start Background Server (delegates to run_server.sh — single source of profile flags)
SERVER_LOG="${SCRIPT_DIR}/server.log"
echo "Starting ROCmFPX llama-server in background..."
echo "  • Backend:       ${DEVICE}"
echo "  • Model:         $(basename "$MODEL_FILE")"
if [ "${CACHE_MODE}" = "cache" ]; then
    echo "  • Speculation:   disabled for checkpoint compatibility"
    echo "  • Prompt Cache:  ${CACHE_PROFILE} profile (${CACHE_RAM_MIB} MiB, ${CTX_CHECKPOINTS} checkpoints)"
else
    echo "  • Speculation:   MTP Speculative Decoding (n_max=4, p_min=0.0)"
    echo "  • Prompt Cache:  ${CACHE_PROFILE} profile — warm-turn prefill reuse with MTP"
fi
echo "  • Reasoning:     ${REASONING} (Budget cap: ${REASONING_BUDGET} tokens)"
echo "  • Logs:          ${SERVER_LOG}"
echo "--------------------------------------------------------------------------------"

# Delegate flag assembly to run_server.sh so quickstart and production share one
# codepath. quickstart only supplies the model, device, and port; run_server
# derives batch/cache/MTP/KV defaults from PROFILE (via CACHE_MODE).
export DEVICE
export CACHE_MODE
# shellcheck disable=SC3030
"${SCRIPT_DIR}/run_server.sh" --port "${PORT}" --host "${HOST}" "${MODEL_FILE}" "$@" > "${SERVER_LOG}" 2>&1 &
SERVER_PID=$!

cleanup() {
    echo -e "\nShutting down background server (PID: ${SERVER_PID})..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    echo "Server stopped."
}
trap cleanup EXIT INT TERM

echo -n "⏳ Waiting for model to load into memory"
READY=0
for i in {1..60}; do
    if curl -s "http://${HOST}:${PORT}/health" 2>/dev/null | grep -q "ok"; then
        READY=1
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo -e "\n❌ Server process terminated unexpectedly! Check ${SERVER_LOG} for details."
        exit 1
    fi
    echo -n "."
    sleep 0.5
done

if [ "$READY" -eq 1 ]; then
    echo -e "\n✅ Server ready on http://${HOST}:${PORT}/v1!"
    echo "================================================================================"
    python3 "${SCRIPT_DIR}/scripts/chat_tui.py" --port "${PORT}"
else
    echo -e "\n❌ Server timed out while loading. Check ${SERVER_LOG}."
    exit 1
fi
