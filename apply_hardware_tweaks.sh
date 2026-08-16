#!/usr/bin/env bash
# ==============================================================================
# apply_hardware_tweaks.sh — Strix Halo Peak Power, Clock & Memory Tuning
# Automatically calculates optimal TTM GTT memory limits for 64GB and 128GB systems
# ==============================================================================

set -e

echo "🔧 Checking and applying Strix Halo hardware optimizations..."

# 1. Lock GPU Clock to High Performance (2.9 GHz)
DPM_PATH="/sys/class/drm/card0/device/power_dpm_force_performance_level"
if [ -w "$DPM_PATH" ]; then
    echo "high" > "$DPM_PATH"
    echo "  [OK] GPU Performance Level locked to 'high' (2.9 GHz RDNA 3.5)"
else
    echo "  [INFO] GPU DPM path requires sudo (run: echo high | sudo tee $DPM_PATH)"
fi

# 2. Transparent Hugepages (THP)
THP_PATH="/sys/kernel/mm/transparent_hugepage/enabled"
if [ -w "$THP_PATH" ]; then
    echo "madvise" > "$THP_PATH"
    echo "  [OK] Transparent Hugepages set to 'madvise'"
else
    echo "  [INFO] THP path requires sudo (run: echo madvise | sudo tee $THP_PATH)"
fi

# 3. Dynamic TTM / GTT Memory Limit (64GB vs 128GB Auto-Detection)
TTM_PATH="/sys/module/ttm/parameters/pages_limit"
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))

if [ "$TOTAL_MEM_GB" -ge 100 ]; then
    # 128GB System: allocate ~120 GiB to GPU (31,457,280 pages of 4KB)
    PAGES_LIMIT=31457280
    TARGET_GB=120
elif [ "$TOTAL_MEM_GB" -ge 48 ]; then
    # 64GB System: allocate ~56 GiB to GPU (14,680,064 pages of 4KB)
    PAGES_LIMIT=14680064
    TARGET_GB=56
else
    # Dynamic 85% allocation for other RAM sizes
    TARGET_GB=$((TOTAL_MEM_GB * 85 / 100))
    PAGES_LIMIT=$((TARGET_GB * 1024 * 1024 / 4))
fi

echo "  [INFO] Detected Total System RAM: ${TOTAL_MEM_GB} GiB"
if [ -w "$TTM_PATH" ]; then
    echo "$PAGES_LIMIT" > "$TTM_PATH"
    echo "  [OK] TTM/GTT Memory Limit set to ${TARGET_GB} GiB (${PAGES_LIMIT} pages)"
else
    echo "  [INFO] To set TTM limit to ${TARGET_GB} GiB, run:"
    echo "         echo $PAGES_LIMIT | sudo tee $TTM_PATH"
fi

# 4. NPU /dev/accel/accel0 Access Check
if [ -e "/dev/accel/accel0" ]; then
    echo "  [OK] AMD XDNA 2 NPU visible at /dev/accel/accel0 (amdxdna module active)"
else
    echo "  [WARN] /dev/accel/accel0 not visible. Ensure amdxdna kernel module is loaded."
fi

echo "🚀 Strix Halo hardware optimization sweep complete!"
