#!/usr/bin/env bash
# ==============================================================================
# convert_and_quant.sh — ROCmFP4 Quantization Pipeline for AMD Strix Halo
# ==============================================================================
# Converts BF16 GGUF weights into ROCmFP4_FAST (4.26 bpw) with MTP head preservation.
#
# Usage:
#   ./scripts/convert_and_quant.sh /path/to/model-BF16.gguf [output_dir]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Strix Halo ROCm Environment
export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.5.1}"
export HIP_VISIBLE_DEVICES="0"
export ROCM_FLUSH_ACCEPT="1"
export RADV_PERFTEST="gpl,sam,nggc"

INPUT_PATH="${1:-}"
OUTPUT_DIR="${2:-$ROOT_DIR/models}"
PRESET="${PRESET:-Q4_0_ROCMFP4_FAST}"

if [ -z "$INPUT_PATH" ]; then
    echo "Usage: $0 /path/to/model-BF16.gguf [output_dir]"
    exit 1
fi

# Find llama-quantize
QUANT_BIN="$(which llama-quantize 2>/dev/null || echo "$ROOT_DIR/engine/bin/llama-quantize")"

if [ ! -x "$QUANT_BIN" ]; then
    echo "❌ Error: llama-quantize binary not found at $QUANT_BIN"
    echo "Please build the engine first using ./build_engine.sh"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
BASENAME="$(basename "$INPUT_PATH" .gguf)"
OUTPUT_FILE="${OUTPUT_DIR}/${BASENAME}-${PRESET}.gguf"

echo "================================================================================"
echo " 🔧 Quantizing Model to ROCmFP4 on AMD Strix Halo"
echo " Input:   $INPUT_PATH"
echo " Output:  $OUTPUT_FILE"
echo " Preset:  $PRESET (Block Size: 32, FP4 Dequant Scale, MTP Preserved)"
echo " Threads: $(nproc)"
echo "================================================================================"

"$QUANT_BIN" \
    "$INPUT_PATH" \
    "$OUTPUT_FILE" \
    "$PRESET" \
    "$(nproc)"

echo "✅ Quantization complete: $OUTPUT_FILE"
