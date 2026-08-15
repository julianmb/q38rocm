#!/usr/bin/env python3
"""
context_scaling_benchmark.py — Long-Context Scaling & Latency Benchmark for Qwen 3.8 27B on Strix Halo
Tests TTFT, prefill throughput, and decode speed across varying context depths (1K, 4K, 8K, 16K, 32K, 64K).
"""

import os
import sys
import time
import json
import argparse
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
BENCHMARK_DIR = ROOT_DIR / "benchmarks"

CONTEXT_DEPTHS = [1024, 4096, 8192, 16384, 32768]

def color(text, code): return f"\033[{code}m{text}\033[0m"
def green(text): return color(text, "1;32")
def yellow(text): return color(text, "1;33")
def cyan(text): return color(text, "1;36")
def bold(text): return color(text, "1")

def generate_context_prompt(target_tokens):
    # Base filler block (~100 tokens)
    block = (
        "The AMD Strix Halo architecture introduces a unified memory subsystem with 128 GB LPDDR5X-8000 "
        "providing 273 GB/s bandwidth shared between 16 Zen 5 CPU cores and 40 RDNA 3.5 compute units. "
        "This heterogeneous layout enables high-throughput LLM inference and long-context processing. "
    )
    # Estimate ~25 words per 30 tokens
    repeat_count = max(1, target_tokens // 30)
    filler = (block * repeat_count)[:target_tokens * 4]
    
    prompt = (
        f"Background information:\n{filler}\n\n"
        f"Question: Based on the text above, summarize the unified memory bandwidth of AMD Strix Halo in one sentence."
    )
    return prompt

def test_context_depth(host, port, target_tokens):
    url = f"http://{host}:{port}/v1/chat/completions"
    prompt = generate_context_prompt(target_tokens)
    
    payload = json.dumps({
        "model": "qwen38-27b",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 64,
        "temperature": 0.0
    }).encode("utf-8")

    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            elapsed = time.time() - t0
            
            timings = data.get("timings", {})
            prompt_n = timings.get("prompt_n", target_tokens)
            prompt_ms = timings.get("prompt_ms", 0.0)
            prefill_tps = (prompt_n / (prompt_ms / 1000.0)) if prompt_ms > 0 else 0.0
            pred_n = timings.get("predicted_n", 0)
            pred_ms = timings.get("predicted_ms", 0.0)
            decode_tps = (pred_n / (pred_ms / 1000.0)) if pred_ms > 0 else 0.0

            return {
                "target_tokens": target_tokens,
                "actual_prompt_tokens": prompt_n,
                "ttft_ms": round(prompt_ms, 2),
                "prefill_tps": round(prefill_tps, 2),
                "completion_tokens": pred_n,
                "decode_tps": round(decode_tps, 2),
                "total_time_s": round(elapsed, 2)
            }
    except Exception as e:
        print(f"Error at {target_tokens} tokens: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description="Strix Halo Long-Context Scaling Benchmark")
    parser.add_argument("--port", type=int, default=8000, help="Server port (default: 8000)")
    parser.add_argument("--host", default="127.0.0.1", help="Server host (default: 127.0.0.1)")
    parser.add_argument("--export-dir", default=str(BENCHMARK_DIR), help="Directory to save reports")
    args = parser.parse_args()

    print("\n" + "=" * 80)
    print(bold(" 📈 QWEN 3.8 27B LONG-CONTEXT SCALING BENCHMARK (STRIX HALO)"))
    print("=" * 80)

    results = []
    for depth in CONTEXT_DEPTHS:
        print(f"Testing context depth: {yellow(f'{depth:,} tokens')}...", end="", flush=True)
        res = test_context_depth(args.host, args.port, depth)
        if res:
            results.append(res)
            ttft_val = res['ttft_ms']
            prefill_val = res['prefill_tps']
            decode_val = res['decode_tps']
            print(f" TTFT: {cyan(f'{ttft_val} ms')} | Prefill: {green(f'{prefill_val} t/s')} | Decode: {green(f'{decode_val} t/s')}")
        else:
            print(" FAILED")

    if not results:
        print("No results collected.")
        sys.exit(1)

    # Export Report
    export_path = Path(args.export_dir)
    export_path.mkdir(parents=True, exist_ok=True)
    ts_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    md_file = export_path / f"context_scaling_{ts_str}.md"
    with open(md_file, "w") as f:
        f.write("# Long-Context Scaling Benchmark Report — Qwen 3.8 27B ROCmFP4\n\n")
        f.write(f"- **Timestamp:** {datetime.now().isoformat()}\n")
        f.write(f"- **Hardware:** AMD Ryzen AI Max+ 395 (40 CU Radeon 8060S / 128 GB UMA)\n")
        f.write(f"- **KV Cache Config:** Asymmetric TurboQuant (`-ctk q8_0 -ctv turbo4`)\n\n")
        f.write("| Target Context | Actual Prompt Tokens | TTFT (Prompt Eval) | Prefill Throughput | Decode Speed |\n")
        f.write("|---|---|---|---|---|\n")
        for r in results:
            f.write(f"| **{r['target_tokens']:,}** | {r['actual_prompt_tokens']:,} | {r['ttft_ms']} ms | {r['prefill_tps']} tok/s | {r['decode_tps']} tok/s |\n")
        f.write("\n---\n*Generated automatically by `scripts/context_scaling_benchmark.py`.*\n")

    print("\n" + "=" * 80)
    print(f"📁 Scaling report saved to: {cyan(str(md_file))}\n")

if __name__ == "__main__":
    main()
