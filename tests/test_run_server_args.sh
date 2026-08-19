#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

touch "$TMP_DIR/model.gguf"
cat > "$TMP_DIR/llama-server" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--list-devices" ]; then
    printf '%s\n' "Vulkan0: mock device"
    exit 0
fi

batch_count=0
ubatch_count=0
no_mmap_count=0
presence_count=0
repeat_count=0
temperature_count=0
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
        *) shift ;;
    esac
done

printf 'batch=%s count=%s\n' "$batch" "$batch_count"
printf 'ubatch=%s count=%s\n' "$ubatch" "$ubatch_count"
printf 'no_mmap_count=%s\n' "$no_mmap_count"
printf 'presence=%s count=%s\n' "$presence" "$presence_count"
printf 'repeat=%s count=%s\n' "$repeat" "$repeat_count"
printf 'temperature=%s count=%s\n' "$temperature" "$temperature_count"
EOF
chmod +x "$TMP_DIR/llama-server"

output="$({
    ROCMFPX_BIN_DIR="$TMP_DIR" \
    MODEL_PATH="$TMP_DIR/model.gguf" \
    "$ROOT_DIR/run_server.sh" \
        -b 1024 \
        -ub 1536 \
        --no-mmap \
        --presence-penalty 0.25 \
        --repeat-penalty 1.02 \
        --temperature 0 \
        --no-mtp
} 2>&1)"

[[ "$output" == *"Model:          model.gguf"* ]]
[[ "$output" == *"batch=1024 count=1"* ]]
[[ "$output" == *"ubatch=1536 count=1"* ]]
[[ "$output" == *"no_mmap_count=1"* ]]
[[ "$output" == *"presence=0.25 count=1"* ]]
[[ "$output" == *"repeat=1.02 count=1"* ]]
[[ "$output" == *"temperature=0 count=1"* ]]

printf '%s\n' "run_server argument tests passed"
