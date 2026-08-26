#!/usr/bin/env bash
# ==============================================================================
# run_server.sh — High-Performance OpenAI-Compatible Server for Qwen 3.8 27B
# Auto-detects Vulkan0 (Mesa RADV Wave64) vs ROCm0 and sets safe reasoning budget
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/setup_env.sh"
source "${SCRIPT_DIR}/scripts/cache_profile.sh"

# 1. Select Profile Defaults, Then Parse Explicit Overrides
MODEL_PATH="${MODEL_PATH:-}"
PORT="${PORT:-8000}"
HOST="${HOST:-127.0.0.1}"
REASONING_BUDGET="${REASONING_BUDGET:-4096}"
DEVICE="${DEVICE:-auto}"
PROFILE="${PROFILE:-${CACHE_MODE:-speed}}"

# Scan args for profile selection before parsing values.
# An explicit --profile always wins; otherwise any cache-enabling flag implies
# the cache profile (issues #12/#13: these flags used to be silently ignored
# while speed/agent kept prompt caching disabled).
EXPLICIT_PROFILE=0
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
    case "${ARGS[$i]}" in
        --profile)
            if ((i + 1 >= ${#ARGS[@]})); then
                echo "--profile requires one of: speed, agent, cache, safe" >&2
                exit 2
            fi
            PROFILE="${ARGS[$((i + 1))]}"
            EXPLICIT_PROFILE=1
            ;;
        --cache-mode|--cache-prompt|--cache-ram|--ctx-checkpoints|--checkpoint-every|--slot-save-path|--cache-reuse)
            if [ "$EXPLICIT_PROFILE" -eq 0 ]; then
                PROFILE="cache"
            fi
            ;;
    esac
done

case "${PROFILE}" in
    speed)
        CTX="${CTX:-131072}"
        MTP="${MTP:-1}"
        STRICT_MTP="${STRICT_MTP:-0}"
        KV_K="${KV_K:-q8_0}"
        KV_V="${KV_V:-turbo4}"
        REASONING="${REASONING:-auto}"
        BATCH_SIZE="${BATCH_SIZE:-2048}"
        UBATCH_SIZE="${UBATCH_SIZE:-1024}"
        TEMPERATURE="${TEMPERATURE:-${TEMP:-0.8}}"
        REPEAT_PENALTY="${REPEAT_PENALTY:-1.05}"
        ;;
    agent)
        CTX="${CTX:-65536}"
        MTP="${MTP:-1}"
        STRICT_MTP="${STRICT_MTP:-1}"
        KV_K="${KV_K:-q8_0}"
        KV_V="${KV_V:-turbo4}"
        REASONING="${REASONING:-off}"
        BATCH_SIZE="${BATCH_SIZE:-2048}"
        UBATCH_SIZE="${UBATCH_SIZE:-1024}"
        TEMPERATURE="${TEMPERATURE:-${TEMP:-0.0}}"
        REPEAT_PENALTY="${REPEAT_PENALTY:-1.0}"
        ;;
    cache)
        CTX="${CTX:-131072}"
        MTP="${MTP:-0}"
        STRICT_MTP="${STRICT_MTP:-0}"
        KV_K="q8_0"
        KV_V="q8_0"
        REASONING="${REASONING:-off}"
        BATCH_SIZE="${BATCH_SIZE:-2048}"
        UBATCH_SIZE="${UBATCH_SIZE:-1024}"
        TEMPERATURE="${TEMPERATURE:-${TEMP:-0.0}}"
        REPEAT_PENALTY="${REPEAT_PENALTY:-1.0}"
        ;;
    safe)
        CTX="${CTX:-65536}"
        MTP=0
        STRICT_MTP=0
        KV_K="${KV_K:-q8_0}"
        KV_V="${KV_V:-q8_0}"
        REASONING="${REASONING:-off}"
        BATCH_SIZE="${BATCH_SIZE:-1024}"
        UBATCH_SIZE="${UBATCH_SIZE:-512}"
        TEMPERATURE="${TEMPERATURE:-${TEMP:-0.0}}"
        REPEAT_PENALTY="${REPEAT_PENALTY:-1.0}"
        ;;
    *)
        echo "Unknown profile '${PROFILE}'. Expected: speed, agent, cache, safe" >&2
        exit 2
        ;;
esac

DRAFT_N="${DRAFT_N:-4}"
DRAFT_P="${DRAFT_P:-0.0}"
PRESENCE_PENALTY="${PRESENCE_PENALTY:-0.0}"
CACHE_MODE="$([ "${PROFILE}" = "cache" ] && printf cache || printf disabled)"
configure_cache_profile
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --ctx) CTX="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --slots) SLOTS="$2"; shift 2 ;;
        --cache-ram) CACHE_RAM_MIB="$2"; shift 2 ;;
        --ctx-checkpoints) CTX_CHECKPOINTS="$2"; shift 2 ;;
        --cache-reuse) CACHE_REUSE="$2"; shift 2 ;;
        --checkpoint-every) CHECKPOINT_EVERY="$2"; shift 2 ;;
        --slot-save-path) SLOT_SAVE_PATH="$2"; shift 2 ;;
        --mlock) MLOCK=1; shift ;;
        --profile) shift 2 ;;
        --cache-mode) shift ;;
        --cache-prompt) shift ;;
        -b|--batch) BATCH_SIZE="$2"; shift 2 ;;
        -ub|--ubatch) UBATCH_SIZE="$2"; shift 2 ;;
        --presence-penalty) PRESENCE_PENALTY="$2"; shift 2 ;;
        --repeat-penalty) REPEAT_PENALTY="$2"; shift 2 ;;
        --temp|--temperature) TEMPERATURE="$2"; shift 2 ;;
        --no-mmap) shift ;;
        --draft-n) DRAFT_N="$2"; shift 2 ;;
        --draft-p) DRAFT_P="$2"; shift 2 ;;
        --no-mtp) MTP=0; shift ;;
        --mtp) MTP=1; shift ;;
        --kv-k) KV_K="$2"; shift 2 ;;
        --kv-v) KV_V="$2"; shift 2 ;;
        --reasoning) REASONING="$2"; shift 2 ;;
        --reasoning-budget) REASONING_BUDGET="$2"; shift 2 ;;
        --no-reasoning) REASONING="off"; shift ;;
        --strict) STRICT_MTP=1; shift ;;
        --no-strict) STRICT_MTP=0; shift ;;
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

# cache profile keeps q8_0/q8_0 KV (TurboQuant rotation is incompatible with
# checkpoint restore). MTP stays off unless explicitly opted in via MTP=1 or
# --mtp: coexistence requires the patched engine (patches/mtp-prompt-cache-fix.patch).
if [ "${PROFILE}" = "cache" ]; then
    KV_K="q8_0"
    KV_V="q8_0"
fi

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

if [ "${PROFILE}" = "cache" ]; then
    mkdir -p "${SLOT_SAVE_PATH}"
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
    "-np" "${SLOTS}"
    "-c" "${CTX}"
    "-b" "${BATCH_SIZE}"
    "-ub" "${UBATCH_SIZE}"
    "-t" "16"
    "--poll" "100"
    "-ctk" "${KV_K}"
    "-ctv" "${KV_V}"
    "--presence-penalty" "${PRESENCE_PENALTY}"
    "--repeat-penalty" "${REPEAT_PENALTY}"
    "--temperature" "${TEMPERATURE}"
    "--no-mmap"
    "--cont-batching"
    "--kv-unified"
    "--port" "${PORT}"
    "--host" "${HOST}"
)

if [ "${PROFILE}" = "cache" ]; then
    CMD+=(
        "-ctxcp" "${CTX_CHECKPOINTS}"
        "-cpent" "${CHECKPOINT_EVERY}"
        "-cram" "${CACHE_RAM_MIB}"
        "--cache-prompt"
        "--cache-reuse" "${CACHE_REUSE}"
        "--slot-save-path" "${SLOT_SAVE_PATH}"
    )
else
    CMD+=("-ctxcp" "0" "-cram" "0" "--no-cache-prompt" "--no-cache-idle-slots")
fi

if [ "${MLOCK}" = "1" ]; then
    CMD+=("--mlock")
fi

if [ "${MTP}" = "1" ]; then
    CMD+=("--spec-type" "draft-mtp" "--spec-draft-n-max" "${DRAFT_N}" "--spec-draft-p-min" "${DRAFT_P}")
    if [ "${STRICT_MTP}" = "1" ]; then
        CMD+=("--spec-mtp-strict-qwen")
    fi
fi

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
echo " Profile:        ${PROFILE}"
echo " Device Backend: ${DEVICE}"
echo " Context:        ${CTX} tokens (KV: K=${KV_K}, V=${KV_V})"
if [ "${PROFILE}" = "cache" ]; then
    echo " Prompt Cache:   ${CACHE_PROFILE} profile (${CACHE_RAM_MIB} MiB, ${CTX_CHECKPOINTS} checkpoints, reuse ${CACHE_REUSE})"
    if [ "${MTP}" = "1" ]; then
        echo " ⚠️  MTP + prompt cache needs a patched engine (built with"
        echo "     patches/mtp-prompt-cache-fix.patch, release v1.5.0+). Divergent prompt"
        echo "     tails will gracefully fall back to cold prefill via spec-boundary-mismatch."
    fi
else
    echo " Prompt Cache:   disabled explicitly (checkpoints=0, RAM cache=0)"
fi
echo " Concurrency:    ${SLOTS} slot(s), continuous batching, unified KV"
echo " Batching:       logical=${BATCH_SIZE}, physical=${UBATCH_SIZE}"
echo " Sampling:       temperature=${TEMPERATURE}, presence=${PRESENCE_PENALTY}, repeat=${REPEAT_PENALTY}"
echo " Speculation:    $([ "${MTP}" = "1" ] && printf 'MTP n_max=%s, p_min=%s, strict=%s' "${DRAFT_N}" "${DRAFT_P}" "${STRICT_MTP}" || printf 'disabled')"
echo " Reasoning:      ${REASONING} (Budget: ${REASONING_BUDGET:-unlimited} tokens)"
echo " API Endpoint:   http://${HOST}:${PORT}/v1"
echo "================================================================================"

exec "${CMD[@]}"
