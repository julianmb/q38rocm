#!/usr/bin/env bash
# ==============================================================================
# benchmark_all.sh — Automated Throughput & Context Scaling Suite for Strix Halo
# ==============================================================================
# Runs llama-bench across prompt contexts (512, 4096, 32768, 131072, 262144) and
# token generation (128 tokens) on AMD Strix Halo (gfx1151).
#
# Usage:
#   ./scripts/benchmark_all.sh /path/to/model.gguf [--dev Vulkan0|ROCm0] [--dry-run]
# ==============================================================================
set -euo pipefail

# Source local .env if present
if [ -f ".env" ]; then
    set -a; source .env; set +a
elif [ -f "../.env" ]; then
    set -a; source ../.env; set +a
fi

# Defaults
DEVICE="${DEVICE:-Vulkan0}"
KV_K="${KV_K:-q8_0}"
KV_V="${KV_V:-q8_0}"
REPEATS="${REPEATS:-3}"
MODEL_PATH="${1:-}"
DRY_RUN=0

if [ -z "$MODEL_PATH" ] || [ "$MODEL_PATH" == "--help" ] || [ "$MODEL_PATH" == "-h" ]; then
    echo "Usage: $0 /path/to/model.gguf [options]"
    echo "Options:"
    echo "  --dev <device>     Set backend device (default: Vulkan0 or env DEVICE)"
    echo "  --ctk <quant>      Set K-cache quant (default: q8_0)"
    echo "  --ctv <quant>      Set V-cache quant (default: q8_0 or turbo4)"
    echo "  --dry-run          Print benchmark commands without executing"
    exit 0
fi

shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dev)     DEVICE="$2"; shift 2 ;;
        --ctk)     KV_K="$2"; shift 2 ;;
        --ctv)     KV_V="$2"; shift 2 ;;
        --repeats) REPEATS="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

BENCH_BIN="ROCmFPX/build-strix-rocmfp4/bin/llama-bench"

if [ ! -f "$BENCH_BIN" ] && [ "$DRY_RUN" -eq 0 ]; then
    echo "Error: llama-bench binary not found at ${BENCH_BIN}." >&2
    echo "       Run ./scripts/build_rocmfpx.sh first." >&2
    exit 1
fi

export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.5.1}"
export GGML_HIP_ENABLE_UNIFIED_MEMORY="${GGML_HIP_ENABLE_UNIFIED_MEMORY:-1}"

echo "=========================================================="
echo " q38rocm: Benchmark & Context Scaling Suite (Strix Halo)"
echo " Model:    ${MODEL_PATH}"
echo " Device:   ${DEVICE} | FlashAttention: ON"
echo " KV Cache: -ctk ${KV_K} -ctv ${KV_V}"
echo " Repeats:  ${REPEATS}"
echo " Dry Run:  ${DRY_RUN}"
echo "=========================================================="

# Test 1: Standard Prompt Fill (512) & Decode (128)
CMD_STD=(
    "$BENCH_BIN"
    -m "$MODEL_PATH"
    -dev "$DEVICE" -ngl 999 -fa on
    -p 512 -n 128
    -ctk "$KV_K" -ctv "$KV_V"
    -r "$REPEATS"
)

# Test 2: Context Scaling Suite (512 to 262144 prompt fill)
CMD_CTX=(
    "$BENCH_BIN"
    -m "$MODEL_PATH"
    -dev "$DEVICE" -ngl 999 -fa on
    -p "512,4096,32768,131072,262144" -n 0
    -ctk "$KV_K" -ctv "$KV_V"
    -r 1
)

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[*] Dry-run enabled. Command preview:"
    echo "  1. Standard benchmark:"
    echo "     ${CMD_STD[*]}"
    echo "  2. Context scaling benchmark:"
    echo "     ${CMD_CTX[*]}"
    exit 0
fi

echo -e "\n[*] Step 1: Running Standard pp512 & tg128 Benchmark..."
"${CMD_STD[@]}"

echo -e "\n[*] Step 2: Running Context Scaling Benchmark (4K -> 262K)..."
"${CMD_CTX[@]}" || echo "[!] Long context benchmark exceeded available system memory or reached context limits."

echo -e "\n=========================================================="
echo " Benchmarking Complete!"
echo "=========================================================="
