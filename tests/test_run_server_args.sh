#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
trap 'echo "=== test failed; captured run_server output: ==="; echo "${output:-<none>}"' ERR

touch "$TMP_DIR/model.gguf"
cat > "$TMP_DIR/llama-server" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--list-devices" ]; then
    printf '%s\n' "Vulkan0: mock device"
    exit 0
fi

batch=""
ubatch=""
presence=""
repeat=""
temperature=""
ctx=""
ctxcp=""
cram=""
strict=""
no_cache_prompt=""
cache_prompt=""
spec_type=""

batch_count=0
ubatch_count=0
no_mmap_count=0
presence_count=0
repeat_count=0
temperature_count=0
ctxcp_count=0
cram_count=0
no_cache_prompt_count=0
cache_prompt_count=0
strict_count=0
ctx_count=0
spec_type_count=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        -b)
            batch_count=$((batch_count + 1))
            batch="$2"
            shift 2
            ;;
        -ub)
            ubatch_count=$((ubatch_count + 1))
            ubatch="$2"
            shift 2
            ;;
        --no-mmap)
            no_mmap_count=$((no_mmap_count + 1))
            shift
            ;;
        --presence-penalty)
            presence_count=$((presence_count + 1))
            presence="$2"
            shift 2
            ;;
        --repeat-penalty)
            repeat_count=$((repeat_count + 1))
            repeat="$2"
            shift 2
            ;;
        --temperature)
            temperature_count=$((temperature_count + 1))
            temperature="$2"
            shift 2
            ;;
        -c)
            ctx_count=$((ctx_count + 1))
            ctx="$2"
            shift 2
            ;;
        -ctxcp)
            ctxcp_count=$((ctxcp_count + 1))
            ctxcp="$2"
            shift 2
            ;;
        -cram)
            cram_count=$((cram_count + 1))
            cram="$2"
            shift 2
            ;;
        --no-cache-prompt)
            no_cache_prompt_count=$((no_cache_prompt_count + 1))
            shift
            ;;
        --cache-prompt)
            cache_prompt_count=$((cache_prompt_count + 1))
            shift
            ;;
        --spec-mtp-strict-qwen)
            strict_count=$((strict_count + 1))
            shift
            ;;
        --spec-type)
            spec_type_count=$((spec_type_count + 1))
            shift
            ;;
        *) shift ;;
    esac
done

printf 'batch=%s count=%s\n' "$batch" "$batch_count"
printf 'ubatch=%s count=%s\n' "$ubatch" "$ubatch_count"
printf 'no_mmap_count=%s\n' "$no_mmap_count"
printf 'presence=%s count=%s\n' "$presence" "$presence_count"
printf 'repeat=%s count=%s\n' "$repeat" "$repeat_count"
printf 'temperature=%s count=%s\n' "$temperature" "$temperature_count"
printf 'ctx=%s count=%s\n' "$ctx" "$ctx_count"
printf 'ctxcp=%s count=%s\n' "$ctxcp" "$ctxcp_count"
printf 'cram=%s count=%s\n' "$cram" "$cram_count"
printf 'no_cache_prompt_count=%s\n' "$no_cache_prompt_count"
printf 'cache_prompt_count=%s\n' "$cache_prompt_count"
printf 'strict_count=%s\n' "$strict_count"
printf 'spec_type_count=%s\n' "$spec_type_count"
EOF
chmod +x "$TMP_DIR/llama-server"

output="$({
    SKIP_ROCM_CHECK=1 \
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" \
        -b 1024 \
        -ub 1536 \
        --no-mmap \
        --presence-penalty 0.25 \
        --repeat-penalty 1.02 \
        --temperature 0 \
        --no-mtp \
        --slot-save-path "$TMP_DIR/slots"
} 2>&1)"

[[ "$output" == *"Model:          model.gguf"* ]]
[[ "$output" == *"batch=1024 count=1"* ]]
[[ "$output" == *"ubatch=1536 count=1"* ]]
[[ "$output" == *"no_mmap_count=1"* ]]
[[ "$output" == *"presence=0.25 count=1"* ]]
[[ "$output" == *"repeat=1.02 count=1"* ]]
[[ "$output" == *"temperature=0 count=1"* ]]
cram_re='cram=[1-9][0-9]* count=1'
[[ "$output" =~ $cram_re ]]
ctxcp_re='ctxcp=[1-9][0-9]* count=1'
[[ "$output" =~ $ctxcp_re ]]
[[ "$output" == *"no_cache_prompt_count=0"* ]]
[[ "$output" == *"cache_prompt_count=1"* ]]

agent_output="$({
    SKIP_ROCM_CHECK=1 \
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" --profile agent
} 2>&1)"

[[ "$agent_output" == *"Profile:        agent"* ]]
[[ "$agent_output" == *"ctx=65536 count=1"* ]]
[[ "$agent_output" == *"ubatch=1024 count=1"* ]]
[[ "$agent_output" == *"temperature=0.0 count=1"* ]]
[[ "$agent_output" == *"strict_count=1"* ]]
[[ "$agent_output" == *"ctxcp=0 count=1"* ]]

safe_output="$({
    SKIP_ROCM_CHECK=1 \
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" --profile safe
} 2>&1)"

[[ "$safe_output" == *"Profile:        safe"* ]]
[[ "$safe_output" == *"ctx=65536 count=1"* ]]
[[ "$safe_output" == *"batch=1024 count=1"* ]]
[[ "$safe_output" == *"ubatch=512 count=1"* ]]
[[ "$safe_output" == *"strict_count=0"* ]]

cache_output="$({
    SKIP_ROCM_CHECK=1 \
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" --profile cache --slot-save-path "$TMP_DIR/slots"
} 2>&1)"

[[ "$cache_output" == *"Profile:        cache"* ]]
[[ "$cache_output" == *"no_cache_prompt_count=0"* ]]
[[ "$cache_output" == *"strict_count=0"* ]]
[[ "$cache_output" == *"spec_type_count=0"* ]]
[[ "$cache_output" == *"temperature=0.0 count=1"* ]]
cram_re='cram=[1-9][0-9]* count=1'
[[ "$cache_output" =~ $cram_re ]]
ctxcp_re='ctxcp=[1-9][0-9]* count=1'
[[ "$cache_output" =~ $ctxcp_re ]]

implied_cache_output="$({
    SKIP_ROCM_CHECK=1 \
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" --cache-prompt --slot-save-path "$TMP_DIR/slots"
} 2>&1)"

[[ "$implied_cache_output" == *"Profile:        cache"* ]]
[[ "$implied_cache_output" == *"cache_prompt_count=1"* ]]
[[ "$implied_cache_output" == *"no_cache_prompt_count=0"* ]]

explicit_profile_wins="$({
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" --cache-prompt --profile agent
} 2>&1)"

[[ "$explicit_profile_wins" == *"Profile:        agent"* ]]
[[ "$explicit_profile_wins" == *"no_cache_prompt_count=1"* ]]
[[ "$explicit_profile_wins" == *"strict_count=1"* ]]

# issue #19: a cache flag with a non-cache profile forces -cram 0, so nothing is
# ever stored — the user must be told instead of silently getting a cold server
[[ "$explicit_profile_wins" == *"forces -cram 0"* ]]
[[ "$explicit_profile_wins" == *"Use --profile cache"* ]]

cache_profile_no_notice="$({
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" --profile cache --slot-save-path "$TMP_DIR/slots"
} 2>&1)"

[[ "$cache_profile_no_notice" != *"forces -cram 0"* ]]

cache_mtp_output="$({
    SKIP_ROCM_CHECK=1 \
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    MTP=1 \
    "$ROOT_DIR/run_server.sh" --profile cache --slot-save-path "$TMP_DIR/slots"
} 2>&1)"

[[ "$cache_mtp_output" == *"Profile:        cache"* ]]
[[ "$cache_mtp_output" == *"spec_type_count=1"* ]]
[[ "$cache_mtp_output" == *"MTP + prompt cache needs engine v1.5.0+"* ]]

cache_mtp_flag_output="$({
    SKIP_ROCM_CHECK=1 \
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" --profile cache --mtp --slot-save-path "$TMP_DIR/slots"
} 2>&1)"

[[ "$cache_mtp_flag_output" == *"spec_type_count=1"* ]]

cache_multislot_output="$({
    SKIP_ROCM_CHECK=1 \
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" --profile cache --slots 4 --slot-save-path "$TMP_DIR/slots"
} 2>&1)"

[[ "$cache_multislot_output" == *"Concurrency:    4 slot(s)"* ]]
[[ "$cache_multislot_output" == *"Profile:        cache"* ]]

printf '%s\n' "run_server argument tests passed"
