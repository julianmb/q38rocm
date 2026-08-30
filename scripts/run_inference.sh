#!/usr/bin/env bash
# ==============================================================================
# run_inference.sh — Legacy wrapper (use ./run_server.sh or ./quickstart.sh)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "⚠️  scripts/run_inference.sh is deprecated — use ./run_server.sh or ./quickstart.sh" >&2
echo "   For CLI chat: ./run_server.sh is for servers; for CLI use the engine directly:" >&2
echo "     \${SCRIPT_DIR}/engine/bin/llama-cli -m <model> -dev Vulkan0 --jinja" >&2

# Map legacy [cli|server] [speed|quality] args to run_server.sh profiles.
MODE="${1:-server}"
VARIANT="${2:-speed}"
MODEL_PATH="${3:-}"
PROFILE="speed"
if [ "${VARIANT}" = "quality" ] || [ "${VARIANT}" = "cache" ]; then
    PROFILE="cache"
elif [ "${VARIANT}" = "safe" ]; then
    PROFILE="safe"
fi

shift 3 2>/dev/null || true
# shellcheck disable=SC2145
echo "   Delegating to: ./run_server.sh --profile ${PROFILE} ${MODEL_PATH:+\"$MODEL_PATH\"} $*" >&2
if [ "${MODE}" = "cli" ]; then
    echo "   Note: CLI mode now runs via llama-cli directly; extra args forwarded to run_server are ignored." >&2
fi
# shellcheck disable=SC2068
exec "${SCRIPT_DIR}/run_server.sh" --profile "${PROFILE}" ${MODEL_PATH:+"$MODEL_PATH"} $@
