#!/usr/bin/env bash

# Select prompt-cache settings from physical RAM while preserving user overrides.
configure_cache_profile() {
    local mem_total_kib="${MEM_TOTAL_KIB_OVERRIDE:-0}"
    local key value unit

    if [ "$mem_total_kib" -eq 0 ] && [ -r /proc/meminfo ]; then
        while read -r key value unit; do
            if [ "$key" = "MemTotal:" ]; then
                mem_total_kib="$value"
                break
            fi
        done < /proc/meminfo
    fi

    if [ "$mem_total_kib" -ge 117440512 ]; then
        CACHE_PROFILE="128GB"
        CACHE_RAM_MIB="${CACHE_RAM_MIB:-32768}"
        CTX_CHECKPOINTS="${CTX_CHECKPOINTS:-16}"
    elif [ "$mem_total_kib" -ge 58720256 ]; then
        CACHE_PROFILE="64GB"
        CACHE_RAM_MIB="${CACHE_RAM_MIB:-16384}"
        CTX_CHECKPOINTS="${CTX_CHECKPOINTS:-8}"
    else
        CACHE_PROFILE="32GB"
        CACHE_RAM_MIB="${CACHE_RAM_MIB:-8192}"
        CTX_CHECKPOINTS="${CTX_CHECKPOINTS:-4}"
    fi

    CACHE_REUSE="${CACHE_REUSE:-256}"
    CHECKPOINT_EVERY="${CHECKPOINT_EVERY:-4096}"
    SLOTS="${SLOTS:-1}"
    MLOCK="${MLOCK:-0}"
    SLOT_SAVE_PATH="${SLOT_SAVE_PATH:-${SCRIPT_DIR}/cache/slots}"
}
