#!/usr/bin/env bash
# ==============================================================================
# download_model.sh — Download Qwen 3.8 27B ROCmFP4_FAST GGUF weights from Hugging Face
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_FILE="${SCRIPT_DIR}/models/Qwen3.8-27B-ROCmFP4-FAST.gguf"
REPO_ID="julianmb/Qwen-3.8-27B-ROCmFP4-FAST-GGUF"
FILENAME="Qwen3.8-27B-ROCmFP4-FAST.gguf"
EXPECTED_SHA256="fb89c78d2be91cdb68eaaaa45b1270710bf34aa721dc1f0b9e3aa7b98d2e1da9"

mkdir -p "${SCRIPT_DIR}/models"

echo "================================================================================"
echo " 📥 Downloading Qwen 3.8 27B ROCmFP4_FAST (13.55 GiB)"
echo " Repository: https://huggingface.co/${REPO_ID}"
echo " Destination: ${TARGET_FILE}"
echo "================================================================================"

if [ -f "$TARGET_FILE" ]; then
    echo "Checking existing file integrity..."
    if command -v sha256sum >/dev/null 2>&1; then
        CURRENT_SHA="$(sha256sum "$TARGET_FILE" | awk '{print $1}')"
        if [ "$CURRENT_SHA" = "$EXPECTED_SHA256" ]; then
            echo "✅ Model already downloaded and checksum verified!"
            exit 0
        else
            echo "⚠️  Existing file checksum mismatch, re-downloading..."
        fi
    fi
fi

if command -v hf >/dev/null 2>&1; then
    echo "Using 'hf' CLI to download..."
    hf download "$REPO_ID" "$FILENAME" --local-dir "$SCRIPT_DIR"
elif command -v huggingface-cli >/dev/null 2>&1; then
    echo "Using 'huggingface-cli' to download..."
    huggingface-cli download "$REPO_ID" "$FILENAME" --local-dir "$SCRIPT_DIR"
else
    echo "Using curl to download from Hugging Face..."
    DOWNLOAD_URL="https://huggingface.co/${REPO_ID}/resolve/main/${FILENAME}"
    curl -L "$DOWNLOAD_URL" -o "$TARGET_FILE" --progress-bar
fi

echo "Verifying SHA256 checksum..."
if command -v sha256sum >/dev/null 2>&1; then
    echo "${EXPECTED_SHA256}  ${TARGET_FILE}" | sha256sum -c -
    echo "✅ Download verified successfully!"
else
    echo "⚠️  sha256sum not found, skipping checksum verification."
fi

echo "🚀 Ready to run: ./run_server.sh"
