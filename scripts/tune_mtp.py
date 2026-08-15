#!/usr/bin/env python3
"""
tune_mtp.py — Automated Multi-Token Prediction (MTP) Speculative Tuning Suite for Strix Halo
Sweeps draft depth (n_max) and probability threshold (p_min) to find optimal decoding throughput.
"""

import os
import sys
import json
import time
import argparse
import subprocess
import urllib.request
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
CONFIG_DIR = ROOT_DIR / "config"
MODELS_FILE = CONFIG_DIR / "models.json"
ENGINE_BIN = ROOT_DIR / "engine" / "bin"
LLAMA_SERVER = ENGINE_BIN / "llama-server"

PROMPTS = [
    {
        "category": "Code Generation",
        "prompt": "Write a Python implementation of a LRU Cache class with get and put methods using an OrderedDict or DoublyLinkedList."
    },
    {
        "category": "Reasoning & Math",
        "prompt": "Solve this step-by-step: If 5 machines make 5 widgets in 5 minutes, how many minutes will 100 machines take to make 100 widgets? Explain why."
    },
    {
        "category": "Structured JSON",
        "prompt": "Extract the entities from this text into valid JSON format with keys: name, role, company, location: 'Sarah Jenkins joined Anthropic as VP of Research in San Francisco.'"
    }
]

def get_env():
    env = os.environ.copy()
    env.update({
        "HSA_OVERRIDE_GFX_VERSION": "11.5.1",
        "GGML_HIP_ENABLE_UNIFIED_MEMORY": "1",
        "HIP_VISIBLE_DEVICES": "0",
        "ROCM_FLUSH_ACCEPT": "1",
        "RADV_PERFTEST": "gpl,sam,nggc",
        "LD_LIBRARY_PATH": f"{ENGINE_BIN}:{os.environ.get('LD_LIBRARY_PATH', '')}"
    })
    return env

def wait_for_server(port, timeout=25):
    url = f"http://127.0.0.1:{port}/health"
    start = time.time()
    while time.time() - start < timeout:
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=1) as resp:
                if resp.status == 200:
                    return True
        except Exception:
            time.sleep(0.4)
    return False

def query_server(port, prompt, max_tokens=150):
    url = f"http://127.0.0.1:{port}/v1/chat/completions"
    payload = json.dumps({
        "model": "strix-test",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0
    }).encode("utf-8")
    
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data
    except Exception as e:
        print(f"Error querying server: {e}")
        return None

def test_config(model_path, device, n_max, p_min, port=8199, max_tokens=150):
    cmd = [
        str(LLAMA_SERVER),
        "-m", str(model_path),
        "-dev", device,
        "-c", "8192",
        "-ngl", "99",
        "-t", "16",
        "-b", "512",
        "-ub", "512",
        "-fa", "on",
        "-ctk", "q8_0",
        "-ctv", "turbo4",
        "--host", "127.0.0.1",
        "--port", str(port)
    ]
    
    if n_max > 0:
        cmd.extend([
            "--spec-type", "draft-mtp",
            "--spec-draft-n-max", str(n_max),
            "--spec-draft-p-min", str(p_min)
        ])
        
    proc = subprocess.Popen(cmd, env=get_env(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    if not wait_for_server(port):
        proc.kill()
        return None
        
    results = []
    for p_item in PROMPTS:
        res = query_server(port, p_item["prompt"], max_tokens=max_tokens)
        if res and "timings" in res:
            t = res["timings"]
            tps = t.get("predicted_per_second", 0)
            draft_n = t.get("draft_n", 0)
            draft_acc = t.get("draft_n_accepted", 0)
            acc_rate = (draft_acc / draft_n * 100) if draft_n > 0 else 0
            results.append({
                "category": p_item["category"],
                "tps": tps,
                "draft_n": draft_n,
                "draft_acc": draft_acc,
                "acc_rate": acc_rate
            })
            
    proc.kill()
    proc.wait()
    return results

def main():
    parser = argparse.ArgumentParser(description="MTP Speculative Decoding Sweep for AMD Strix Halo")
    parser.add_argument("--model-file", help="Path to GGUF model file")
    parser.add_argument("--model-id", default="qwen38-27b", help="Model ID in registry")
    parser.add_argument("--device", default="Vulkan0", choices=["Vulkan0", "ROCm0"], help="Backend device")
    parser.add_argument("--max-tokens", type=int, default=150, help="Max tokens per test query")
    parser.add_argument("--draft-n-list", default="0,3,4,5,6", help="Comma-separated draft-n values to test (0=baseline)")
    parser.add_argument("--draft-p-list", default="0.50,0.55", help="Comma-separated draft-p values to test")
    parser.add_argument("--port", type=int, default=8200, help="Base port for server testing")
    args = parser.parse_args()

    model_path = None
    if args.model_file:
        model_path = Path(args.model_file)
    else:
        if MODELS_FILE.exists():
            data = json.loads(MODELS_FILE.read_text(encoding="utf-8"))
            m = data.get("models", {}).get(args.model_id, {})
            quants = m.get("quant_files", {})
            for qk in ["ROCmFP4_FAST", "ROCmFP4_STRIX_LEAN", list(quants.keys())[0] if quants else ""]:
                if qk in quants:
                    p = ROOT_DIR / quants[qk]
                    if p.exists():
                        model_path = p
                        break

    if not model_path or not model_path.exists():
        print(f"Error: Could not locate valid model file for '{args.model_id}'.")
        sys.exit(1)

    print("\n" + "=" * 80)
    print(" 🚀 AUTOMATED MTP SPECULATIVE TUNING SWEEP FOR STRIX HALO")
    print(f" Model:  {model_path.name}")
    print(f" Device: {args.device}")
    print("=" * 80 + "\n")

    n_vals = [int(x.strip()) for x in args.draft_n_list.split(",") if x.strip()]
    p_vals = [float(x.strip()) for x in args.draft_p_list.split(",") if x.strip()]

    summary_rows = []

    for n in n_vals:
        if n == 0:
            print(f"[*] Testing Baseline (No MTP)...")
            res = test_config(model_path, args.device, n_max=0, p_min=0, port=args.port, max_tokens=args.max_tokens)
            if res:
                avg_tps = sum(r["tps"] for r in res) / len(res)
                summary_rows.append({
                    "config": "Baseline (No MTP)",
                    "n": 0,
                    "p": 0.0,
                    "avg_tps": avg_tps,
                    "acc_rate": 0.0,
                    "details": res
                })
                print(f"    -> Average TPS: {avg_tps:.2f} tok/s\n")
        else:
            for p in p_vals:
                print(f"[*] Testing MTP Profile: n_max={n}, p_min={p:.2f}...")
                res = test_config(model_path, args.device, n_max=n, p_min=p, port=args.port, max_tokens=args.max_tokens)
                if res:
                    avg_tps = sum(r["tps"] for r in res) / len(res)
                    tot_n = sum(r["draft_n"] for r in res)
                    tot_acc = sum(r["draft_acc"] for r in res)
                    avg_acc = (tot_acc / tot_n * 100) if tot_n > 0 else 0
                    summary_rows.append({
                        "config": f"MTP (n={n}, p={p:.2f})",
                        "n": n,
                        "p": p,
                        "avg_tps": avg_tps,
                        "acc_rate": avg_acc,
                        "details": res
                    })
                    print(f"    -> Average TPS: {avg_tps:.2f} tok/s (Acceptance: {avg_acc:.1f}%)\n")

    print("\n" + "=" * 80)
    print(" 📊 MTP TUNING SUMMARY & PERFORMANCE MATRIX")
    print("=" * 80)
    print(f"{'Configuration':<24} | {'Avg TPS (tok/s)':<16} | {'Speedup vs Base':<16} | {'Draft Accept %':<14}")
    print("-" * 80)

    base_tps = summary_rows[0]["avg_tps"] if summary_rows else 1.0
    best_row = max(summary_rows, key=lambda x: x["avg_tps"]) if summary_rows else None

    for row in summary_rows:
        sp = row["avg_tps"] / base_tps
        acc_str = f"{row['acc_rate']:.1f}%" if row['n'] > 0 else "N/A"
        print(f"{row['config']:<24} | {row['avg_tps']:<16.2f} | {sp:<16.2f}x | {acc_str:<14}")

    print("=" * 80)
    if best_row and best_row["n"] > 0:
        sp_best = best_row["avg_tps"] / base_tps
        print(f"\n🏆 RECOMMENDED OPTIMAL PROFILE: {best_row['config']}")
        print(f"   Peak Average Throughput: {best_row['avg_tps']:.2f} tok/s ({sp_best:.2f}x speedup over baseline)")
        print(f"   Launch arguments: --spec-type draft-mtp --spec-draft-n-max {best_row['n']} --spec-draft-p-min {best_row['p']:.2f}\n")

if __name__ == "__main__":
    main()
