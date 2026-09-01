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
HUB_DIR="${HALOFPX_HUB_DIR:-${HOME}/source/halofpx-research}"
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
CACHE_FLAGS_SEEN=0
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
            CACHE_FLAGS_SEEN=1
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
        TEMPERATURE="${TEMPERATURE:-${TEMP:-0.0}}"
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
    structured)
        CTX="${CTX:-65536}"
        MTP=0
        STRICT_MTP=0
        KV_K="${KV_K:-q8_0}"
        KV_V="${KV_V:-q8_0}"
        REASONING="${REASONING:-off}"
        BATCH_SIZE="${BATCH_SIZE:-2048}"
        UBATCH_SIZE="${UBATCH_SIZE:-2048}"
        TEMPERATURE="${TEMPERATURE:-${TEMP:-0.0}}"
        REPEAT_PENALTY="${REPEAT_PENALTY:-1.0}"
        DRAFT_N_MIN="${DRAFT_N_MIN:-3}"
        DRAFT_N_MAX="${DRAFT_N_MAX:-7}"
        DRAFT_ADAPTIVE=1
        ;;
    *)
        echo "Unknown profile '${PROFILE}'. Expected: speed, agent, cache, safe, structured" >&2
        exit 2
        ;;
esac

DRAFT_N="${DRAFT_N:-4}"
DRAFT_P="${DRAFT_P:-0.0}"
DRAFT_N_MIN="${DRAFT_N_MIN:-3}"
DRAFT_N_MAX="${DRAFT_N_MAX:-7}"
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

# cache profile keeps q8_0/q8_0 KV (measured safest for arbitrary branching).
# MTP in the cache profile stays off unless explicitly opted in via MTP=1 or
# --mtp. The speed profile combines MTP + prompt caching + TurboQuant KV —
# validated on v1.5.2+: divergent-tail turns restore from checkpoints instead
# of cold-refilling (7.6x faster warm turns, decode unchanged).
if [ "${PROFILE}" = "cache" ]; then
    KV_K="q8_0"
    KV_V="q8_0"
fi

# speed, cache and structured profiles enable prompt caching (RAM checkpoints);
# agent/safe keep caching fully disabled for conservative isolation.
USE_CACHE=0
case "${PROFILE}" in
    speed|cache|structured) USE_CACHE=1 ;;
esac

# structured profile guards: fail closed if engine lacks draft-dflash,
# and warn on unsafe parallel slots (cross-request leakage on Strix Halo).
if [ "${PROFILE}" = "structured" ]; then
    if [ "${SLOTS:-1}" != "1" ] && [ "${SLOTS:-1}" != "" ]; then
        echo "❌ --profile structured requires --slots 1 (parallel slots leak on gfx1151, see docs). Use speed or cache for -np>1." >&2
        exit 2
    fi
fi

# 2. Resolve Model Path
if [ -z "$MODEL_PATH" ]; then
    if [ -f "${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP4-FAST.gguf" ]; then
        MODEL_PATH="${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP4-FAST.gguf"
    elif [ -f "${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP8.gguf" ]; then
        MODEL_PATH="${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP8.gguf"
    elif [ -f "${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf" ]; then
        MODEL_PATH="${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf"
    elif [ -f "${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP8.gguf" ]; then
        MODEL_PATH="${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP8.gguf"
    elif [ -f "${HUB_DIR:-/nonexistent}/models/qwen38-27b/Qwen3.8-27B-ROCmFP4-FAST.gguf" ]; then
        MODEL_PATH="${HUB_DIR:-/nonexistent}/models/qwen38-27b/Qwen3.8-27B-ROCmFP4-FAST.gguf"
    else
        MODEL_PATH="${SCRIPT_DIR}/Qwen3.8-27B-ROCmFP4-FAST.gguf"
    fi
fi

if [ "${USE_CACHE}" = "1" ]; then
    mkdir -p "${SLOT_SAVE_PATH}"
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "⚠️  Model file not found at: $MODEL_PATH"
    echo "Please download the weights using:"
    echo "  ./download_model.sh"
    echo "or specify the path: ./run_server.sh /path/to/model.gguf"
    exit 1
fi

# Asking for caching without the cache profile is a no-op: the other profiles pass
# `-cram 0`, so --cache-prompt has nowhere to store a state and every prompt is
# reprocessed (issue #19: an agent switch on -np 1 then looks like a cache bug).
if [ "$CACHE_FLAGS_SEEN" = "1" ] && [ "${PROFILE}" != "cache" ]; then
    echo "⚠️  [NOTICE] --profile ${PROFILE} forces -cram 0, so prompt caching stores nothing." >&2
    echo "   ${PROFILE} profile + a cache flag = cache enabled in name only." >&2
    echo "   Use --profile cache, or add --cache-ram <MiB> explicitly." >&2
    echo "--------------------------------------------------------------------------------" >&2
fi

# 3. Locate llama-server Binary
LLAMA_SERVER_BIN="$(which llama-server 2>/dev/null || true)"
if [ -z "$LLAMA_SERVER_BIN" ] && [ -x "${SCRIPT_DIR}/engine/bin/llama-server" ]; then
    LLAMA_SERVER_BIN="${SCRIPT_DIR}/engine/bin/llama-server"
elif [ -z "$LLAMA_SERVER_BIN" ] && [ -x "/home/user/source/halofpx-research/engine/bin/llama-server" ]; then
    LLAMA_SERVER_BIN="/home/user/source/halofpx-research/engine/bin/llama-server"
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

if [ "${USE_CACHE}" = "1" ]; then
    CMD+=(
        "-ctxcp" "${CTX_CHECKPOINTS}"
        "-cpent" "${CHECKPOINT_EVERY}"
        "-cram" "${CACHE_RAM_MIB}"
        "--cache-prompt"
        "--slot-save-path" "${SLOT_SAVE_PATH}"
    )
    if [ "${PROFILE}" = "cache" ]; then
        CMD+=("--cache-reuse" "${CACHE_REUSE}")
    fi
else
    CMD+=("-ctxcp" "0" "-cram" "0" "--no-cache-prompt" "--no-cache-idle-slots")
fi

if [ "${MLOCK}" = "1" ]; then
    CMD+=("--mlock")
fi

if [ "${PROFILE}" = "structured" ]; then
    DRAFT_MODEL="${DRAFT_MODEL:-${SCRIPT_DIR}/models/Qwen3.8-27B-DFlash2-Q4_K_M.gguf}"
    if [ ! -f "${DRAFT_MODEL}" ] && [ -f "${SCRIPT_DIR}/Qwen3.8-27B-DFlash2-Q4_K_M.gguf" ]; then
        DRAFT_MODEL="${SCRIPT_DIR}/Qwen3.8-27B-DFlash2-Q4_K_M.gguf"
    fi
    if [ ! -f "${DRAFT_MODEL}" ]; then
        echo "❌ --profile structured requires a DFlash2 draft model." >&2
        echo "   Expected: ${SCRIPT_DIR}/models/Qwen3.8-27B-DFlash2-Q4_K_M.gguf" >&2
        echo "   Download: huggingface-cli download incoai/Qwen3.8-27B-DFlash2-GGUF Qwen3.8-27B-DFlash2-Q4_K_M.gguf --local-dir ${SCRIPT_DIR}/models" >&2
        exit 1
    fi
    if ! "${LLAMA_SERVER_BIN}" --help 2>&1 | grep -q "draft-dflash"; then
        echo "❌ Engine does not support --spec-type draft-dflash (need LaurentZuijdwijk/llama.cpp or ROCmFPX with DFlash2)." >&2
        exit 1
    fi
    CMD+=("--spec-type" "draft-dflash" "--spec-draft-n-min" "${DRAFT_N_MIN}" "--spec-draft-n-max" "${DRAFT_N_MAX}" "--spec-draft-p-min" "0.0" "--spec-draft-adaptive")
    CMD+=("-md" "${DRAFT_MODEL}" "-ngld" "99" "--device-draft" "${DEVICE}")
elif [ "${MTP}" = "1" ]; then
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
if [ "${USE_CACHE}" = "1" ]; then
    echo " Prompt Cache:   ${CACHE_PROFILE} profile (${CACHE_RAM_MIB} MiB, ${CTX_CHECKPOINTS} checkpoints)"
    if [ "${MTP}" = "1" ]; then
        echo " ⚠️  MTP + prompt cache needs engine v1.5.0+ (current release is fine)."
        echo "     Older engines gracefully fall back to cold prefill on divergent tails."
    fi
else
    echo " Prompt Cache:   disabled explicitly (checkpoints=0, RAM cache=0)"
fi
echo " Concurrency:    ${SLOTS} slot(s), continuous batching, unified KV"
echo " Batching:       logical=${BATCH_SIZE}, physical=${UBATCH_SIZE}"
echo " Sampling:       temperature=${TEMPERATURE}, presence=${PRESENCE_PENALTY}, repeat=${REPEAT_PENALTY}"
echo " Speculation:    $([ "${PROFILE}" = "structured" ] && printf 'DFlash2 n_min=%s n_max=%s adaptive' "${DRAFT_N_MIN}" "${DRAFT_N_MAX}" || ([ "${MTP}" = "1" ] && printf 'MTP n_max=%s, p_min=%s, strict=%s' "${DRAFT_N}" "${DRAFT_P}" "${STRICT_MTP}" || printf 'disabled'))"
echo " Reasoning:      ${REASONING} (Budget: ${REASONING_BUDGET:-unlimited} tokens)"
echo " API Endpoint:   http://${HOST}:${PORT}/v1"
echo "================================================================================"

exec "${CMD[@]}"
