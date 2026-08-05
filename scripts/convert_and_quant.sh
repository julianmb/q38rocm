#!/usr/bin/env bash
# ==============================================================================
# convert_and_quant.sh — Pipeline Template: BF16/FP8 -> GGUF -> ROCmFPX
# ==============================================================================
# Usage: ./scripts/convert_and_quant.sh /path/to/hf_model_dir ./output_dir
set -euo pipefail

INPUT_DIR="${1:-}"
OUTPUT_DIR="${2:-./output_quantized}"

if [ -z "$INPUT_DIR" ] || [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Please specify a valid Hugging Face model input directory."
    echo "Usage: $0 /path/to/hf_model_dir [output_dir]"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

QUANT_BIN="ROCmFPX/build-strix-rocmfp4/bin/llama-quantize"
if [ ! -f "$QUANT_BIN" ]; then
    echo "Error: llama-quantize binary not found. Run ./scripts/build_rocmfpx.sh first."
    exit 1
fi

INTERMEDIATE_F16="$OUTPUT_DIR/model-f16.gguf"
SPEED_OUTPUT="$OUTPUT_DIR/model-ROCmFPX-Speed.gguf"
QUALITY_OUTPUT="$OUTPUT_DIR/model-ROCmFPX-Quality.gguf"

echo "=========================================================="
echo " Step 1: Converting Hugging Face model to F16 GGUF...      "
echo "=========================================================="
python3 ROCmFPX/convert_hf_to_gguf.py "$INPUT_DIR" \
    --outfile "$INTERMEDIATE_F16" \
    --outtype f16

echo "=========================================================="
echo " Step 2A: Quantizing Speed Variant (Q4_0_ROCMFP4_COHERENT) "
echo "=========================================================="
"$QUANT_BIN" "$INTERMEDIATE_F16" "$SPEED_OUTPUT" Q4_0_ROCMFP4_COHERENT

echo "=========================================================="
echo " Step 2B: Quantizing Quality Variant (Q6_0_ROCMFPX_AGENT)  "
echo "=========================================================="
"$QUANT_BIN" "$INTERMEDIATE_F16" "$QUALITY_OUTPUT" Q6_0_ROCMFPX_AGENT

echo "=========================================================="
echo " Step 3: Generating Checksums                              "
echo "=========================================================="
cd "$OUTPUT_DIR"
sha256sum "$(basename "$SPEED_OUTPUT")" "$(basename "$QUALITY_OUTPUT")" > SHA256SUMS

echo "=========================================================="
echo " Conversion & Quantization Complete!"
echo " Outputs saved in: $OUTPUT_DIR"
echo "=========================================================="
