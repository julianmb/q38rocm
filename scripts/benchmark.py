#!/usr/bin/env python3
"""
benchmark.py — Automated Performance & Latency Benchmark Runner for Qwen 3.8 27B on Strix Halo
Measures TTFT, Decode TPS, and MTP Draft Acceptance, auto-exporting Markdown & JSON reports.
"""

import os
import sys
import time
import json
import argparse
import subprocess
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
BENCHMARK_DIR = ROOT_DIR / "benchmarks"

BENCHMARK_PROMPTS = [
    {
        "category": "Code Generation",
        "name": "Binary Search Tree (Python)",
        "prompt": "Write a complete binary search tree implementation in Python with insert, search, and inorder traversal methods.",
        "max_tokens": 200
    },
    {
        "category": "Reasoning & Logic",
        "name": "Math Puzzle (Widget Factory)",
        "prompt": "Solve step-by-step: If 5 machines take 5 minutes to make 5 widgets, how many minutes do 100 machines take to make 100 widgets?",
        "max_tokens": 150
    },
    {
        "category": "Structured Extraction",
        "name": "JSON Entity Extractor",
        "prompt": "Extract the entities from this text into valid JSON format with keys: name, role, company, location: 'Sarah Jenkins joined Anthropic as VP of Research in San Francisco.'",
        "max_tokens": 100
    },
    {
        "category": "Technical Writing",
        "name": "UMA vs Discrete Architecture",
        "prompt": "Explain the architectural difference between unified memory architecture (UMA) and discrete GPU memory in three concise bullet points.",
        "max_tokens": 150
    }
]

def color(text, code): return f"\033[{code}m{text}\033[0m"
def green(text): return color(text, "1;32")
def yellow(text): return color(text, "1;33")
def cyan(text): return color(text, "1;36")
def bold(text): return color(text, "1")

def get_system_telemetry():
    telemetry = {
        "cpu_model": "AMD Ryzen AI Max+ 395",
        "kernel": os.uname().release,
        "ram_gb": 128.0,
        "gpu_target": "gfx1151 (Radeon 8060S)",
        "timestamp": datetime.now().isoformat()
    }
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "model name" in line:
                    telemetry["cpu_model"] = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass
    return telemetry

from collections import Counter

def detect_repetition(text: str, n_gram_size: int = 3, threshold: int = 6) -> bool:
    words = text.split()
    if len(words) < n_gram_size * threshold:
        return False
    ngrams = [tuple(words[i:i+n_gram_size]) for i in range(len(words) - n_gram_size + 1)]
    counts = Counter(ngrams)
    return any(count >= threshold for count in counts.values())

def get_active_model(host: str, port: int) -> str:
    # Try rocmfpx management endpoint
    try:
        url = f"http://{host}:{port}/api/v1/status"
        with urllib.request.urlopen(url, timeout=2) as r:
            data = json.loads(r.read().decode())
            m = data.get("engine", {}).get("model_id")
            if m:
                return m
    except Exception:
        pass
    
    # Try OpenAI models endpoint
    try:
        url = f"http://{host}:{port}/v1/models"
        with urllib.request.urlopen(url, timeout=2) as r:
            data = json.loads(r.read().decode())
            models = data.get("data", [])
            for item in models:
                if item.get("is_active"):
                    return item.get("id")
            if models:
                return models[0].get("id", "qwen38-27b")
    except Exception:
        pass

    return "qwen38-27b"

def run_prompt_benchmark(host, port, prompt_data, model_name="qwen38-27b"):
    url = f"http://{host}:{port}/v1/chat/completions"
    payload = json.dumps({
        "model": model_name,
        "messages": [{"role": "user", "content": prompt_data["prompt"]}],
        "max_tokens": prompt_data["max_tokens"],
        "temperature": 0.0
    }).encode("utf-8")

    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            elapsed = time.time() - t0
            
            content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
            is_repeating = detect_repetition(content)
            
            timings = data.get("timings", {})
            prompt_ms = timings.get("prompt_ms", 0.0)
            prompt_n = timings.get("prompt_n", 0)
            pred_ms = timings.get("predicted_ms", elapsed * 1000)
            pred_n = timings.get("predicted_n", 0)
            pred_tps = timings.get("predicted_per_second", (pred_n / (pred_ms / 1000.0)) if pred_ms > 0 else 0)
            draft_n = timings.get("draft_n", 0)
            draft_acc = timings.get("draft_n_accepted", 0)
            acc_rate = (draft_acc / draft_n * 100.0) if draft_n > 0 else 0.0

            return {
                "name": prompt_data["name"],
                "category": prompt_data["category"],
                "prompt_tokens": prompt_n,
                "ttft_ms": round(prompt_ms, 2),
                "completion_tokens": pred_n,
                "decode_ms": round(pred_ms, 2),
                "decode_tps": round(pred_tps, 2),
                "draft_tokens": draft_n,
                "draft_accepted": draft_acc,
                "draft_acceptance_pct": round(acc_rate, 1),
                "repetition_detected": is_repeating,
                "total_time_s": round(elapsed, 2)
            }
    except Exception as e:
        print(f"Error executing benchmark: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description="ROCmFPX Benchmark Reporter")
    parser.add_argument("--model", type=str, default=None, help="Target model identifier (auto-detected if omitted)")
    parser.add_argument("--port", type=int, default=8000, help="Server port (default: 8000)")
    parser.add_argument("--host", default="127.0.0.1", help="Server host (default: 127.0.0.1)")
    parser.add_argument("--export-dir", default=str(BENCHMARK_DIR), help="Directory to save reports")
    args = parser.parse_args()

    # Health check
    health_url = f"http://{args.host}:{args.port}/health"
    try:
        with urllib.request.urlopen(health_url, timeout=5) as r:
            pass
    except Exception:
        print(f"❌ Server not reachable on {health_url}. Please start server with ./run_server.sh or rocmfpx serve.")
        sys.exit(1)

    model_name = args.model or get_active_model(args.host, args.port)

    print("\n" + "=" * 80)
    print(bold(f" 📊 RUNNING ROCmFPX BENCHMARK SUITE — Model: {model_name}"))
    print("=" * 80)
    
    telemetry = get_system_telemetry()
    print(f" Host APU:      {cyan(telemetry['cpu_model'])}")
    print(f" Kernel:        {telemetry['kernel']}")
    print(f" GPU Target:    {telemetry['gpu_target']}")
    print("-" * 80)

    results = []
    for idx, p in enumerate(BENCHMARK_PROMPTS, 1):
        print(f"[{idx}/{len(BENCHMARK_PROMPTS)}] Benchmarking: {yellow(p['name'])}...", end="", flush=True)
        res = run_prompt_benchmark(args.host, args.port, p, model_name=model_name)
        if res:
            results.append(res)
            tps_val = res['decode_tps']
            print(f" {green(f'{tps_val} tok/s')} | TTFT: {res['ttft_ms']}ms | MTP Acc: {res['draft_acceptance_pct']}%")
        else:
            print(" FAILED")

    if not results:
        print("No benchmark results collected.")
        sys.exit(1)

    # Calculate summary averages
    avg_tps = sum(r["decode_tps"] for r in results) / len(results)
    avg_ttft = sum(r["ttft_ms"] for r in results) / len(results)
    avg_acc = sum(r["draft_acceptance_pct"] for r in results if r["draft_tokens"] > 0) / len(results)

    print("\n" + "=" * 80)
    print(bold(f" 🏁 BENCHMARK SUMMARY: Average Decode = {green(f'{avg_tps:.2f} tok/s')} | Average TTFT = {avg_ttft:.1f}ms | MTP Acceptance = {avg_acc:.1f}%"))
    print("=" * 80)

    # Export Reports
    export_path = Path(args.export_dir)
    export_path.mkdir(parents=True, exist_ok=True)
    ts_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # JSON Report
    json_file = export_path / f"benchmark_{ts_str}.json"
    report_data = {
        "telemetry": telemetry,
        "summary": {
            "average_decode_tps": round(avg_tps, 2),
            "average_ttft_ms": round(avg_ttft, 2),
            "average_draft_acceptance_pct": round(avg_acc, 1),
            "total_prompts": len(results)
        },
        "results": results
    }
    with open(json_file, "w") as f:
        json.dump(report_data, f, indent=2)

    # Markdown Report
    md_file = export_path / f"benchmark_{ts_str}.md"
    with open(md_file, "w") as f:
        f.write(f"# Strix Halo Benchmark Report — Qwen 3.8 27B ROCmFP4\n\n")
        f.write(f"- **Timestamp:** {telemetry['timestamp']}\n")
        f.write(f"- **APU Hardware:** {telemetry['cpu_model']}\n")
        f.write(f"- **Kernel / Driver:** {telemetry['kernel']} / Mesa RADV\n")
        f.write(f"- **Average Decode Throughput:** **{avg_tps:.2f} tok/s**\n")
        f.write(f"- **Average TTFT:** **{avg_ttft:.2f} ms**\n")
        f.write(f"- **MTP Acceptance Rate:** **{avg_acc:.1f}%**\n\n")
        f.write("## Benchmark Results by Task\n\n")
        f.write("| Task | Category | Decode Speed | TTFT | Completion Tokens | MTP Acceptance |\n")
        f.write("|---|---|---|---|---|---|\n")
        for r in results:
            f.write(f"| **{r['name']}** | {r['category']} | {r['decode_tps']} tok/s | {r['ttft_ms']} ms | {r['completion_tokens']} | {r['draft_acceptance_pct']}% |\n")
        f.write("\n---\n*Generated automatically by `scripts/benchmark.py` on AMD Strix Halo.*\n")

    print(f"📁 Reports exported to:")
    print(f"  • Markdown: {cyan(str(md_file))}")
    print(f"  • JSON:     {cyan(str(json_file))}\n")

if __name__ == "__main__":
    main()
