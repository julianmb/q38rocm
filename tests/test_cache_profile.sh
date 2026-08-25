#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR"
source "$ROOT_DIR/scripts/cache_profile.sh"

check_profile() {
    local mem_kib="$1" expected_name="$2" expected_cache="$3" expected_checkpoints="$4"
    unset CACHE_PROFILE CACHE_RAM_MIB CTX_CHECKPOINTS CACHE_REUSE CHECKPOINT_EVERY SLOTS MLOCK SLOT_SAVE_PATH
    MEM_TOTAL_KIB_OVERRIDE="$mem_kib" configure_cache_profile
    [ "$CACHE_PROFILE" = "$expected_name" ]
    [ "$CACHE_RAM_MIB" = "$expected_cache" ]
    [ "$CTX_CHECKPOINTS" = "$expected_checkpoints" ]
}

check_profile 33554432 32GB 8192 16
check_profile 67108864 64GB 16384 32
check_profile 134217728 128GB 32768 64

unset CACHE_PROFILE CTX_CHECKPOINTS
CACHE_RAM_MIB=24576
MEM_TOTAL_KIB_OVERRIDE=134217728 configure_cache_profile
[ "$CACHE_RAM_MIB" = "24576" ]

echo "cache profile tests passed"
