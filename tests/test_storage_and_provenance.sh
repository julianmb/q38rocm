#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
trap 'echo "=== test failed at line $LINENO: $BASH_COMMAND ==="; for v in vulkan_output rocm_output spec_output; do [ -n "${!v:-}" ] && { echo "--- \$$v ---"; echo "${!v}"; }; done' ERR

download_sha_line="$(grep -m1 '^EXPECTED_SHA256=' "$ROOT_DIR/download_model.sh")"
download_sha="${download_sha_line#EXPECTED_SHA256=\"}"
download_sha="${download_sha%\"}"
filename_line="$(grep -m1 '^FILENAME=' "$ROOT_DIR/download_model.sh")"
filename="${filename_line#FILENAME=\"}"
filename="${filename%\"}"
sha256sums_line="$(grep -m1 "  ${filename}$" "$ROOT_DIR/SHA256SUMS")"
published_sha="${sha256sums_line%% *}"

[[ "$download_sha" =~ ^[0-9a-f]{64}$ ]]
[[ "$published_sha" = "$download_sha" ]]

touch "$TMP_DIR/model.gguf"
cat > "$TMP_DIR/llama-server" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--list-devices" ]; then
    printf '%s\n' "${MOCK_DEVICES:-}"
    exit 0
fi

device=""
cram=""
ctxcp=""
spec=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        -dev) device="$2"; shift 2 ;;
        -cram) cram="$2"; shift 2 ;;
        -ctxcp) ctxcp="$2"; shift 2 ;;
        --spec-type) spec=1; shift 2 ;;
        *) shift ;;
    esac
done

printf 'device=%s\n' "$device"
printf 'cram=%s\n' "$cram"
printf 'ctxcp=%s\n' "$ctxcp"
printf 'spec=%s\n' "$spec"

if [ "${MOCK_SPEC_LOG:-0}" = "1" ] && [ "$spec" = "1" ]; then
    if [[ "$cram" =~ ^[1-9][0-9]*$ ]] && [[ "$ctxcp" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s\n' "checkpoint rollback restored"
    else
        printf '%s\n' "cold fallback"
    fi
fi
EOF
chmod +x "$TMP_DIR/llama-server"

run_mock_server() {
    env \
        PATH="$TMP_DIR:$PATH" \
        SKIP_ROCM_CHECK=1 \
        ROCMFPX_BIN_DIR="$TMP_DIR" \
        MODEL_PATH="$TMP_DIR/model.gguf" \
        SLOT_SAVE_PATH="$TMP_DIR/slots" \
        MEM_TOTAL_KIB_OVERRIDE=67108864 \
        "$ROOT_DIR/run_server.sh" "$@"
}

vulkan_output="$(MOCK_DEVICES=$'Vulkan0: mock RADV\nROCm0: mock HIP' run_mock_server --profile safe 2>&1)"
[[ "$vulkan_output" == *"Device Backend: Vulkan0"* ]]
[[ "$vulkan_output" == *"device=Vulkan0"* ]]

rocm_output="$(MOCK_DEVICES='ROCm0: mock HIP' run_mock_server --profile safe 2>&1)"
[[ "$rocm_output" == *"Device Backend: ROCm0"* ]]
[[ "$rocm_output" == *"device=ROCm0"* ]]
[[ "$rocm_output" == *"Falling back to 'ROCm0'"* ]]

# Regression for the MTP empty-data_spec boundary path: the speed launcher must
# retain RAM checkpoints so a compatible engine can roll back instead of doing
# a cold fallback. The mock emits the observed engine outcome from those flags.
spec_output="$(MOCK_DEVICES='Vulkan0: mock RADV' MOCK_SPEC_LOG=1 run_mock_server --profile speed 2>&1)"
[[ "$spec_output" == *"spec=1"* ]]
cram_re='cram=[1-9][0-9]*'
ctxcp_re='ctxcp=[1-9][0-9]*'
[[ "$spec_output" =~ $cram_re ]]
[[ "$spec_output" =~ $ctxcp_re ]]
[[ "$spec_output" == *"checkpoint rollback restored"* ]]
[[ "$spec_output" != *"cold fallback"* ]]

dockerfile="$(<"$ROOT_DIR/Dockerfile")"
[[ "$dockerfile" == *"groupadd render"* ]]
[[ "$dockerfile" == *"mesa-vulkan-drivers"* ]]

# -cram is the aggregate checkpoint RAM cap; checkpoint count times interval
# verifies that each documented target context can be represented.
hardware_doc="$(<"$ROOT_DIR/docs/HARDWARE-AND-MEMORY.md")"
[[ "$hardware_doc" == *'| **32,768 tokens** | **~36.6 GiB**'* ]]
[[ "$hardware_doc" == *'| **131,072 tokens** | ~50 GiB'* ]]
[[ "$hardware_doc" == *'| **262,144 tokens** *(Max)* | **~85 GiB**'* ]]

SCRIPT_DIR="$ROOT_DIR"
source "$ROOT_DIR/scripts/cache_profile.sh"

check_memory_budget() {
    local mem_kib="$1" context_tokens="$2" footprint_mib="$3"
    local model_mib=18791

    unset CACHE_PROFILE CACHE_RAM_MIB CTX_CHECKPOINTS CACHE_REUSE CHECKPOINT_EVERY SLOTS MLOCK SLOT_SAVE_PATH
    MEM_TOTAL_KIB_OVERRIDE="$mem_kib" configure_cache_profile
    [ $((model_mib + CACHE_RAM_MIB)) -le "$footprint_mib" ]
    [ $((CTX_CHECKPOINTS * CHECKPOINT_EVERY)) -ge "$context_tokens" ]
}

check_memory_budget 67108864 32768 37478
check_memory_budget 67108864 131072 51200
check_memory_budget 134217728 262144 87040

printf '%s\n' "storage, provenance, device, cache+MTP, Docker, and memory tests passed"
