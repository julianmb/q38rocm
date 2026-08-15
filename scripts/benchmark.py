#!/usr/bin/env python3
"""
eval_qwen38_full_matrix.py — Rigorous Multi-Stage Optimization Benchmark for Qwen 3.8 27B on Strix Halo
Compares Initial Baseline vs Progressive Optimization Stages on identical workloads.
"""

import os
import sys
import json
import time
import subprocess
import urllib.request
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
ENGINE_BIN = ROOT_DIR / "engine" / "bin"
LLAMA_SERVER = ENGINE_BIN / "llama-server"

STOCK_MODEL = "/var/lib/lemonade/.cache/huggingface/hub/models--unsloth--Qwen3.8-27B-GGUF/snapshots/4604b899a826000505a834e623272db5b7fd62f6/Qwen3.8-27B-Q4_K_M.gguf"
ROCMFP4_LEAN = str(ROOT_DIR / "models/qwen38-27b/Qwen3.8-27B-ROCmFP4-STRIX_LEAN.gguf")
ROCMFP4_FAST = str(ROOT_DIR / "models/qwen38-27b/Qwen3.8-27B-ROCmFP4-FAST.gguf")

BENCHMARK_PROMPTS = [
    {
        "name": "Code (Binary Search Tree)",
        "prompt": "Write a complete binary search tree implementation in Python with insert, search, and inorder traversal methods.",
        "max_tokens": 200
    },
    {
        "name": "Reasoning & Math",
        "prompt": "Solve step-by-step: If 5 machines take 5 minutes to make 5 widgets, how many minutes do 100 machines take to make 100 widgets?",
        "max_tokens": 150
    },
    {
        "name": "Structured JSON Extraction",
        "prompt": "Extract the entities from this text into valid JSON format with keys: name, role, company, location: 'Sarah Jenkins joined Anthropic as VP of Research in San Francisco.'",
        "max_tokens": 100
    },
    {
        "name": "Technical Explanation",
        "prompt": "Explain the architectural difference between unified memory architecture (UMA) and discrete GPU memory in three concise bullet points.",
        "max_tokens": 150
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

def wait_for_server(port, timeout=30):
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
        "model": "qwen38-eval",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0
    }).encode("utf-8")
    
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data
    except Exception as e:
        print(f"Query error on port {port}: {e}")
        return None

def evaluate_configuration(stage_name, model_path, server_args, port=8787):
    print(f"\n================================================================================")
    print(f" 🧪 Testing Configuration: {stage_name}")
    print(f"================================================================================")
    
    cmd = [
        str(LLAMA_SERVER),
        "-m", model_path,
        "-dev", "Vulkan0",
        "-c", "16384",
        "-ngl", "99",
        "-t", "16",
        "--host", "127.0.0.1",
        "--port", str(port)
    ] + server_args

    proc = subprocess.Popen(cmd, env=get_env(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    if not wait_for_server(port):
        print(f"Error: Server failed to start for '{stage_name}' on port {port}.")
        proc.kill()
        proc.wait()
        return None

    results = []
    for test in BENCHMARK_PROMPTS:
        res = query_server(port, test["prompt"], max_tokens=test["max_tokens"])
        if res and "timings" in res:
            t = res["timings"]
            prompt_tps = t.get("prompt_per_second", 0)
            gen_tps = t.get("predicted_per_second", 0)
            ttft_ms = t.get("prompt_ms", 0)
            draft_n = t.get("draft_n", 0)
            draft_acc = t.get("draft_n_accepted", 0)
            acc_pct = (draft_acc / draft_n * 100) if draft_n > 0 else 0
            
            print(f"  • {test['name']:<28} | Decode: {gen_tps:5.2f} tok/s | TTFT: {ttft_ms:6.1f} ms | MTP Accept: {acc_pct:4.1f}%")
            results.append({
                "task": test["name"],
                "prompt_tps": prompt_tps,
                "gen_tps": gen_tps,
                "ttft_ms": ttft_ms,
                "draft_n": draft_n,
                "draft_acc": draft_acc,
                "acc_pct": acc_pct
            })
        else:
            print(f"  • {test['name']:<28} | FAILED")

    proc.kill()
    proc.wait()
    time.sleep(1)

    if results:
        avg_gen_tps = sum(r["gen_tps"] for r in results) / len(results)
        avg_prompt_tps = sum(r["prompt_tps"] for r in results) / len(results)
        avg_ttft = sum(r["ttft_ms"] for r in results) / len(results)
        total_draft_n = sum(r["draft_n"] for r in results)
        total_draft_acc = sum(r["draft_acc"] for r in results)
        overall_acc = (total_draft_acc / total_draft_n * 100) if total_draft_n > 0 else 0
        
        print(f"  ------------------------------------------------------------------------------")
        print(f"  ⭐ AVERAGE: Generation = {avg_gen_tps:.2f} tok/s | Prompt = {avg_prompt_tps:.2f} tok/s | MTP Accept = {overall_acc:.1f}%")
        
        return {
            "stage_name": stage_name,
            "avg_gen_tps": avg_gen_tps,
            "avg_prompt_tps": avg_prompt_tps,
            "avg_ttft_ms": avg_ttft,
            "overall_acc": overall_acc,
            "details": results
        }
    return None

def main():
    stages = [
        {
            "name": "1. Initial Baseline (Stock Q4_K_M, No MTP, No TurboQuant)",
            "model": STOCK_MODEL,
            "args": ["-b", "512", "-ub", "512", "-np", "4", "-ctk", "f16", "-ctv", "f16"]
        },
        {
            "name": "2. ROCmFP4 Lean (Weight Layout Optimization, No MTP)",
            "model": ROCMFP4_LEAN,
            "args": ["-b", "512", "-ub", "512", "-np", "4", "-fa", "on", "-ctk", "q8_0", "-ctv", "turbo4"]
        },
        {
            "name": "3. ROCmFP4 Fast (Speed-First Quant, No MTP)",
            "model": ROCMFP4_FAST,
            "args": ["-b", "512", "-ub", "512", "-np", "4", "-fa", "on", "-ctk", "q8_0", "-ctv", "turbo4"]
        },
        {
            "name": "4. ROCmFP4 Fast + MTP Self-Speculation (n5 / p0.50)",
            "model": ROCMFP4_FAST,
            "args": ["-b", "512", "-ub", "256", "-np", "1", "-ctxcp", "0", "-cram", "16384", "-fa", "on", "-ctk", "q8_0", "-ctv", "turbo4", "--spec-type", "draft-mtp", "--spec-draft-n-max", "5", "--spec-draft-p-min", "0.50"]
        },
        {
            "name": "5. ROCmFP4 Fast + Deep MTP (Author n6 / p0.60)",
            "model": ROCMFP4_FAST,
            "args": ["-b", "512", "-ub", "256", "-np", "1", "-ctxcp", "0", "-cram", "16384", "-fa", "on", "-ctk", "q8_0", "-ctv", "turbo4", "--spec-type", "draft-mtp", "--spec-draft-n-max", "6", "--spec-draft-p-min", "0.60"]
        },
        {
            "name": "6. ROCmFP4 Fast + Strict Lossless Greedy MTP (--spec-mtp-strict-qwen)",
            "model": ROCMFP4_FAST,
            "args": ["-b", "512", "-ub", "256", "-np", "1", "-ctxcp", "0", "-cram", "16384", "-fa", "on", "-ctk", "q8_0", "-ctv", "turbo4", "--spec-type", "draft-mtp", "--spec-draft-n-max", "6", "--spec-draft-p-min", "0.60", "--spec-mtp-strict-qwen"]
        },
        {
            "name": "7. ROCmFP4 Fast + Composed MTP & N-Gram (Multi-Spec Queue)",
            "model": ROCMFP4_FAST,
            "args": ["-b", "512", "-ub", "256", "-np", "1", "-ctxcp", "0", "-cram", "16384", "-fa", "on", "-ctk", "q8_0", "-ctv", "turbo4", "--spec-type", "draft-mtp,ngram-simple", "--spec-draft-n-max", "6", "--spec-draft-p-min", "0.60"]
        },
        {
            "name": "8. ROCmFP4 Fast + Deep Spec (n7 / p0.35)",
            "model": ROCMFP4_FAST,
            "args": ["-b", "512", "-ub", "256", "-np", "1", "-ctxcp", "0", "-cram", "16384", "-fa", "on", "-ctk", "q8_0", "-ctv", "turbo4", "--spec-type", "draft-mtp", "--spec-draft-n-max", "7", "--spec-draft-p-min", "0.35"]
        }
    ]

    all_stage_results = []
    
    print("\n" + "=" * 80)
    print(" 🚀 STARTING QWEN 3.8 27B FULL OPTIMIZATION MATRIX BENCHMARK")
    print(" Hardware: AMD Strix Halo (Ryzen AI Max+ 395 / Radeon 8060S / 128 GB UMA)")
    print("=" * 80)

    for st in stages:
        res = evaluate_configuration(st["name"], st["model"], st["args"])
        if res:
            all_stage_results.append(res)

    print("\n\n" + "=" * 85)
    print(" 📊 QWEN 3.8 27B COMPREHENSIVE INITIAL VS OPTIMIZED MATRIX")
    print("=" * 85)
    print(f"{'Optimization Stage':<50} | {'Decode TPS':<11} | {'Speedup':<8} | {'MTP Acc %':<9}")
    print("-" * 85)

    base_tps = all_stage_results[0]["avg_gen_tps"] if all_stage_results else 1.0

    for r in all_stage_results:
        sp = r["avg_gen_tps"] / base_tps
        acc_str = f"{r['overall_acc']:.1f}%" if r["overall_acc"] > 0 else "N/A"
        print(f"{r['stage_name'][:50]:<50} | {r['avg_gen_tps']:>6.2f} t/s | {sp:>6.2f}x | {acc_str:>8}")
    print("=" * 85 + "\n")

    # Save output report
    report_file = ROOT_DIR / "docs/QWEN38_OPTIMIZATION_REPORT.md"
    
    md = f"""# 📊 Qwen 3.8 27B Optimization Report: Initial Baseline vs. Fully Tuned Strix Halo Stack

*Benchmark Date: {time.strftime('%Y-%m-%d %H:%M:%S')}*
*Hardware: AMD Strix Halo (Ryzen AI Max+ 395, 40 CU Radeon 8060S gfx1151, 128 GB LPDDR5X-8000)*

---

## 🚀 Executive Summary

| Optimization Stage | Quantization | Generation (tok/s) | Speedup vs Baseline | MTP Draft Acceptance |
|---|---|---|---|---|
"""
    for r in all_stage_results:
        sp = r["avg_gen_tps"] / base_tps
        acc_str = f"{r['overall_acc']:.1f}%" if r["overall_acc"] > 0 else "N/A"
        md += f"| **{r['stage_name']}** | `{Path(r['stage_name']).name}` | **{r['avg_gen_tps']:.2f} tok/s** | **{sp:.2f}×** | {acc_str} |\n"

    md += """
---

## 📈 Detailed Breakdown by Workload Category

"""
    for r in all_stage_results:
        md += f"### {r['stage_name']}\n\n"
        md += "| Benchmark Task | Decode Speed (tok/s) | TTFT (ms) | MTP Acceptance |\n"
        md += "|---|---|---|---|\n"
        for d in r["details"]:
            acc = f"{d['acc_pct']:.1f}%" if d['draft_n'] > 0 else "N/A"
            md += f"| **{d['task']}** | {d['gen_tps']:.2f} tok/s | {d['ttft_ms']:.1f} ms | {acc} |\n"
        md += f"\n*Stage Average: **{r['avg_gen_tps']:.2f} tok/s** (Speedup: **{r['avg_gen_tps']/base_tps:.2f}×**)*\n\n"

    report_file.write_text(md, encoding="utf-8")
    print(f"[+] Successfully wrote complete report to: {report_file}")

if __name__ == "__main__":
    main()
