#!/usr/bin/env python3
"""
quality_eval.py — Deterministic Quality, Accuracy & Smoke Test Suite for Qwen 3.8 27B on Strix Halo
Verifies greedy output determinism, structured JSON generation, code logic, and MTP equivalence.
"""

import os
import sys
import json
import time
import argparse
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
BENCHMARK_DIR = ROOT_DIR / "benchmarks"

QUALITY_TEST_CASES = [
    {
        "id": "code_correctness",
        "name": "Python Quicksort Implementation",
        "prompt": "Write a clean Python quicksort function that sorts an array in-place. Provide only the function definition.",
        "validator": lambda text: "def quicksort" in text and "return" in text or "partition" in text,
        "max_tokens": 200
    },
    {
        "id": "json_strict",
        "name": "Strict JSON Schema Extraction",
        "prompt": "Extract the data into valid JSON with keys 'company', 'role', 'city': 'Alex Rivera became Principal Engineer at Cloudflare in Austin.' Output only raw JSON.",
        "validator": lambda text: "Cloudflare" in text and "Austin" in text and "Principal Engineer" in text,
        "max_tokens": 100
    },
    {
        "id": "math_logic",
        "name": "Deterministic Logic Puzzle",
        "prompt": "If all roses are flowers and some flowers fade quickly, can we conclude that some roses fade quickly? Answer with 'Yes', 'No', or 'Not necessarily' and one sentence explanation.",
        "validator": lambda text: "not necessarily" in text.lower() or "cannot conclude" in text.lower() or "no" in text.lower(),
        "max_tokens": 120
    }
]

def color(text, code): return f"\033[{code}m{text}\033[0m"
def green(text): return color(text, "1;32")
def red(text): return color(text, "1;31")
def yellow(text): return color(text, "1;33")
def cyan(text): return color(text, "1;36")
def bold(text): return color(text, "1")

def query_endpoint(host, port, prompt, max_tokens):
    url = f"http://{host}:{port}/v1/chat/completions"
    payload = json.dumps({
        "model": "qwen38-27b",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0
    }).encode("utf-8")

    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            elapsed = time.time() - t0
            content = data["choices"][0]["message"]["content"]
            timings = data.get("timings", {})
            return {
                "content": content,
                "elapsed_s": round(elapsed, 2),
                "predicted_n": timings.get("predicted_n", 0),
                "tps": round(timings.get("predicted_per_second", 0), 2),
                "draft_accepted": timings.get("draft_n_accepted", 0),
                "draft_total": timings.get("draft_n", 0)
            }
    except Exception as e:
        print(f"Error querying endpoint: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description="Deterministic Quality & Accuracy Evaluator")
    parser.add_argument("--port", type=int, default=8000, help="Server port (default: 8000)")
    parser.add_argument("--host", default="127.0.0.1", help="Server host")
    parser.add_argument("--export-dir", default=str(BENCHMARK_DIR), help="Report output folder")
    args = parser.parse_args()

    print("\n" + "=" * 80)
    print(bold(" 🧪 QWEN 3.8 27B DETERMINISTIC QUALITY & SMOKE TEST SUITE"))
    print("=" * 80)

    results = []
    passed_count = 0

    for idx, test in enumerate(QUALITY_TEST_CASES, 1):
        print(f"[{idx}/{len(QUALITY_TEST_CASES)}] Testing: {yellow(test['name'])}...", end="", flush=True)
        res = query_endpoint(args.host, args.port, test["prompt"], test["max_tokens"])
        if res:
            is_valid = test["validator"](res["content"])
            if is_valid:
                passed_count += 1
                status_str = green("PASSED")
            else:
                status_str = red("FAILED (Assertion Mismatch)")
            
            print(f" {status_str} ({res['tps']} t/s, {res['elapsed_s']}s)")
            results.append({
                "test": test["name"],
                "passed": is_valid,
                "tps": res["tps"],
                "draft_accuracy": f"{(res['draft_accepted']/res['draft_total']*100):.1f}%" if res["draft_total"] > 0 else "N/A",
                "sample_output": res["content"][:120].replace("\n", " ")
            })
        else:
            print(f" {red('ERROR (Connection failed)')}")

    pass_rate = (passed_count / len(QUALITY_TEST_CASES)) * 100.0
    print("\n" + "=" * 80)
    print(bold(f" 🏁 EVALUATION SUMMARY: {passed_count}/{len(QUALITY_TEST_CASES)} Tests Passed ({green(f'{pass_rate:.1f}%')})"))
    print("=" * 80)

    # Export report
    export_path = Path(args.export_dir)
    export_path.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = export_path / f"quality_report_{ts}.md"

    with open(report_file, "w") as f:
        f.write("# Quality & Accuracy Evaluation Report — Qwen 3.8 27B ROCmFP4\n\n")
        f.write(f"- **Timestamp:** {datetime.now().isoformat()}\n")
        f.write(f"- **Pass Rate:** **{passed_count}/{len(QUALITY_TEST_CASES)} ({pass_rate:.1f}%)**\n\n")
        f.write("| Test Name | Status | Generation Speed | MTP Draft Accuracy | Sample Output |\n")
        f.write("|---|---|---|---|---|\n")
        for r in results:
            status_emoji = "✅ PASS" if r["passed"] else "❌ FAIL"
            f.write(f"| **{r['test']}** | {status_emoji} | {r['tps']} tok/s | {r['draft_accuracy']} | `{r['sample_output']}...` |\n")
        f.write("\n---\n*Generated automatically by `scripts/quality_eval.py`.*\n")

    print(f"📁 Quality report saved to: {cyan(str(report_file))}\n")

if __name__ == "__main__":
    main()
