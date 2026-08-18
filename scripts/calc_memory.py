#!/usr/bin/env python3
# ==============================================================================
# calc_memory.py — Strix Halo Memory Footprint & Context Calculator
# ==============================================================================
# Calculates weight footprint, KV cache size, and total peak RAM usage for
# models (including dense, MoE, and hybrid linear/full attention architectures)
# across ROCmFPX quantization presets and context lengths on Strix Halo (gfx1151).
#
# Usage:
#   python3 scripts/calc_memory.py --repo "Qwen/Qwen3.6-27B"
#   python3 scripts/calc_memory.py --config /path/to/config.json
#   python3 scripts/calc_memory.py --params 27 --layers 64 --full-attn-layers 16 --kv-heads 4 --head-dim 256
# ==============================================================================
import sys
import os
import argparse
import json
import urllib.request

# ROCmFPX Preset Bits Per Weight (bpw) mapping
PRESETS = {
    "Q2_0_ROCMFPX": {"bpw": 2.50, "desc": "ROCmFP2 ultra-lean (~2.50 bpw)"},
    "Q4_0_ROCMFP4_COHERENT": {"bpw": 4.00, "desc": "Speed preset (~4.00 bpw)"},
    "Q4_0_ROCMFP4_FAST": {"bpw": 4.25, "desc": "Speed-extreme preset (~4.25 bpw)"},
    "Q4_0_ROCMFP4_STRIX_LEAN": {"bpw": 4.50, "desc": "Strix Halo primary (~4.50 bpw)"},
    "Q6_0_ROCMFPX_AGENT": {"bpw": 6.00, "desc": "Quality preset (~6.00 bpw)"},
    "Q8_0": {"bpw": 8.50, "desc": "8-bit reference (~8.50 bpw)"},
    "F16": {"bpw": 16.00, "desc": "Half precision baseline (~16.00 bpw)"},
}

# KV Cache bytes per value per token
KV_QUANT_BYTES = {
    "q8_0": 1.0,      # 8 bits = 1 byte
    "q4_0": 0.5,      # 4 bits = 0.5 byte
    "turbo4": 0.5,    # 4 bits = 0.5 byte
    "f16": 2.0,       # 16 bits = 2 bytes
}

def fetch_config_from_hf(repo_slug):
    url = f"https://huggingface.co/{repo_slug}/raw/main/config.json"
    req = urllib.request.Request(url, headers={"User-Agent": "q38rocm-calc/1.0"})
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        print(f"Error fetching config.json from HF repo '{repo_slug}': {e}", file=sys.stderr)
        sys.exit(1)

def parse_config_dict(c):
    tc = c.get("text_config") if isinstance(c.get("text_config"), dict) else c

    n_params_b = c.get("num_parameters")
    n_layers = tc.get("num_hidden_layers") or tc.get("num_layers") or 32
    hidden_size = tc.get("hidden_size") or 4096
    n_attn_heads = tc.get("num_attention_heads") or 32
    n_kv_heads = tc.get("num_key_value_heads") or n_attn_heads
    head_dim = tc.get("head_dim") or (hidden_size // n_attn_heads if hidden_size and n_attn_heads else 128)

    layer_types = tc.get("layer_types") or []
    full_attn_layers = sum(1 for t in layer_types if t and "full" in t)
    linear_attn_layers = sum(1 for t in layer_types if t and "linear" in t)
    if not full_attn_layers:
        full_attn_layers = n_layers # Non-hybrid default

    n_experts = tc.get("num_experts") or tc.get("num_local_experts") or 0
    mtp_layers = tc.get("mtp_num_hidden_layers") or 0
    arch = c.get("architectures", ["Unknown"])[0] if c.get("architectures") else "Unknown"

    # Estimate parameter count if not provided
    if not n_params_b:
        intermediate = tc.get("intermediate_size") or (hidden_size * 4)
        vocab = tc.get("vocab_size") or 150000
        # Rough calculation for dense Transformer
        per_layer = (4 * hidden_size * hidden_size) + (2 * hidden_size * intermediate)
        if n_experts:
            per_layer += (n_experts - 1) * (hidden_size * intermediate)
        est_params = (per_layer * n_layers) + (vocab * hidden_size)
        n_params_b = est_params / 1e9

    return {
        "arch": arch,
        "n_params_b": n_params_b,
        "n_layers": n_layers,
        "full_attn_layers": full_attn_layers,
        "linear_attn_layers": linear_attn_layers,
        "n_kv_heads": n_kv_heads,
        "head_dim": head_dim,
        "n_experts": n_experts,
        "mtp_layers": mtp_layers,
        "hybrid": bool(layer_types and linear_attn_layers > 0)
    }

def main():
    parser = argparse.ArgumentParser(description="Strix Halo LLM Memory Footprint & Context Calculator")
    parser.add_argument("--repo", help="Hugging Face repo slug (e.g. Qwen/Qwen3.6-27B)")
    parser.add_argument("--config", help="Path to local config.json file")
    parser.add_argument("--params", type=float, help="Total model parameters in Billions (e.g. 27 or 35)")
    parser.add_argument("--layers", type=int, default=64, help="Total layers (default: 64)")
    parser.add_argument("--full-attn-layers", type=int, help="Number of full-attention layers (for hybrid models)")
    parser.add_argument("--kv-heads", type=int, default=4, help="Number of KV heads (default: 4)")
    parser.add_argument("--head-dim", type=int, default=256, help="Head dimension (default: 256)")
    parser.add_argument("--os-overhead", type=float, default=3.0, help="OS overhead in GiB (default: 3.0)")

    args = parser.parse_args()

    if args.repo:
        print(f"[*] Fetching configuration for HF repo '{args.repo}'...")
        cfg = parse_config_dict(fetch_config_from_hf(args.repo))
    elif args.config:
        print(f"[*] Loading configuration from '{args.config}'...")
        with open(args.config, 'r') as f:
            cfg = parse_config_dict(json.load(f))
    elif args.params:
        full_layers = args.full_attn_layers if args.full_attn_layers is not None else args.layers
        cfg = {
            "arch": "Custom Specification",
            "n_params_b": args.params,
            "n_layers": args.layers,
            "full_attn_layers": full_layers,
            "linear_attn_layers": args.layers - full_layers,
            "n_kv_heads": args.kv_heads,
            "head_dim": args.head_dim,
            "n_experts": 0,
            "mtp_layers": 0,
            "hybrid": (full_layers < args.layers)
        }
    else:
        # Default fallback to Qwen3.6-27B reference
        print("[*] No model specified. Using Qwen3.6-27B reference topology...")
        cfg = {
            "arch": "Qwen3_5ForConditionalGeneration",
            "n_params_b": 27.0,
            "n_layers": 64,
            "full_attn_layers": 16,
            "linear_attn_layers": 48,
            "n_kv_heads": 4,
            "head_dim": 256,
            "n_experts": 0,
            "mtp_layers": 1,
            "hybrid": True
        }

    print("==========================================================")
    print(" q38rocm: AMD Strix Halo Memory Footprint Calculator")
    print("==========================================================")
    print(f" Architecture        : {cfg['arch']}")
    print(f" Parameters          : {cfg['n_params_b']:.2f} Billion")
    print(f" Total Layers        : {cfg['n_layers']}")
    if cfg['hybrid']:
        print(f" Attention Structure : HYBRID ({cfg['full_attn_layers']} full-attn + {cfg['linear_attn_layers']} linear-attn)")
    else:
        print(f" Attention Structure : FULL ({cfg['full_attn_layers']} layers)")
    print(f" KV Heads / Head Dim : {cfg['n_kv_heads']} heads @ {cfg['head_dim']} dim")
    print("==========================================================")

    # 1. Calculate Per-Token KV Cache Size
    # KV per token = 2 (K+V) * full_attn_layers * n_kv_heads * head_dim
    bytes_per_tok_f16 = 2 * cfg['full_attn_layers'] * cfg['n_kv_heads'] * cfg['head_dim'] * 2
    bytes_per_tok_q8 = bytes_per_tok_f16 / 2
    bytes_per_tok_turbo4 = bytes_per_tok_f16 * (1.0 + 0.5) / 4.0 # K=q8_0 (1B), V=turbo4 (0.5B)

    print("\n1. KV Cache Footprint Per Token:")
    print(f"   F16 KV Cache      : {bytes_per_tok_f16} bytes/token ({bytes_per_tok_f16/1024/1024:.3f} MiB)")
    print(f"   q8_0 KV Cache     : {bytes_per_tok_q8} bytes/token ({bytes_per_tok_q8/1024/1024:.3f} MiB)")
    print(f"   q8_0/turbo4 Cache : {bytes_per_tok_turbo4} bytes/token ({bytes_per_tok_turbo4/1024/1024:.3f} MiB)")

    # 2. Weight Footprints Across Presets
    print("\n2. Model Weight Sizes Across ROCmFPX Presets:")
    weight_sizes = {}
    for preset, pinfo in PRESETS.items():
        size_gb = (cfg['n_params_b'] * 1e9 * (pinfo['bpw'] / 8.0)) / (1024**3)
        weight_sizes[preset] = size_gb
        print(f"   {preset:<25}: ~{size_gb:>5.2f} GiB  ({pinfo['desc']})")

    # 3. Context Memory Matrix (using primary STRIX_LEAN quant)
    strix_lean_gb = weight_sizes.get("Q4_0_ROCMFP4_STRIX_LEAN", weight_sizes["Q4_0_ROCMFP4_COHERENT"])
    contexts = [4096, 16384, 32768, 131072, 262144]

    print("\n3. Total System RAM Footprint vs Context Length (STRIX_LEAN + q8_0/turbo4 KV):")
    print("   -----------------------------------------------------------------------------------------")
    print("   Context   | KV (q8/turbo4) | + Weights  | + OS Overhead | Total Peak RAM | 32GB | 64GB | 128GB")
    print("   -----------------------------------------------------------------------------------------")

    for ctx in contexts:
        kv_gb = (bytes_per_tok_turbo4 * ctx) / (1024**3)
        total_ram = strix_lean_gb + kv_gb + args.os_overhead

        c32 = "  ✅ " if total_ram <= 30 else "  ❌ "
        c64 = "  ✅ " if total_ram <= 60 else "  ❌ "
        c128 = " ✅ " if total_ram <= 120 else " ❌ "

        print(f"   {ctx:>7}  |   {kv_gb:>5.2f} GiB   | {strix_lean_gb:>5.2f} GiB |   {args.os_overhead:>4.1f} GiB    |   {total_ram:>6.2f} GiB  |{c32}|{c64}|{c128}")

    print("   -----------------------------------------------------------------------------------------")
    print("   Note: Hybrid linear/full attention significantly reduces KV memory compared to pure dense models.")

if __name__ == "__main__":
    main()
