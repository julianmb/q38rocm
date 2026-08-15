#!/usr/bin/env bash
# ==============================================================================
# apply_hardware_tweaks.sh — Strix Halo Peak Power & Clock Governor Tuning
# ==============================================================================

set -e

echo "🔧 Checking and applying Strix Halo hardware optimizations..."

# 1. Lock GPU Clock to High Performance (2.9 GHz)
DPM_PATH="/sys/class/drm/card0/device/power_dpm_force_performance_level"
if [ -w "$DPM_PATH" ]; then
    echo "high" > "$DPM_PATH"
    echo "  [OK] GPU Performance Level locked to 'high' (2.9 GHz RDNA 3.5)"
else
    echo "  [INFO] GPU DPM path not directly writable without sudo. Run with sudo if possible."
fi

# 2. Transparent Hugepages (THP)
THP_PATH="/sys/kernel/mm/transparent_hugepage/enabled"
if [ -w "$THP_PATH" ]; then
    echo "always" > "$THP_PATH"
    echo "  [OK] Transparent Hugepages set to 'always'"
else
    echo "  [INFO] THP path requires root permissions to modify."
fi

# 3. NPU /dev/accel/accel0 Access Check
if [ -e "/dev/accel/accel0" ]; then
    echo "  [OK] AMD XDNA 2 NPU visible at /dev/accel/accel0 (amdxdna module active)"
else
    echo "  [WARN] /dev/accel/accel0 not visible. Ensure amdxdna module is loaded."
fi

echo "🚀 Strix Halo hardware optimization sweep complete!"
