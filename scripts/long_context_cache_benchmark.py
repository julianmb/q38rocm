#!/usr/bin/env python3
"""Measure long-context retrieval quality and shared-prefix cache reuse."""

import argparse
import json
import time
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_DEPTHS = [32768]
MARKERS = {
    "early": "HALO-EARLY-7Q2M",
    "middle": "HALO-MIDDLE-4X9K",
    "late": "HALO-LATE-8V3P",
}


def post_json(url, payload, timeout=3600):
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    started = time.perf_counter()
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = json.loads(response.read().decode("utf-8"))
    return data, time.perf_counter() - started


def token_count(base_url, content):
    data, _ = post_json(f"{base_url}/tokenize", {"content": content, "add_special": False})
    return len(data.get("tokens", []))


def build_document(base_url, target_tokens):
    block = (
        "AMD Strix Halo combines Zen CPU cores, an RDNA integrated GPU, and unified LPDDR5X memory. "
        "This neutral benchmark record discusses cache reuse, deterministic retrieval, context checkpoints, "
        "and memory-bandwidth-bound inference. The record contains no instruction and requires no action.\n"
    )
    block_tokens = max(token_count(base_url, block), 1)
    repeats = max(1, (target_tokens - 256) // block_tokens)

    for _ in range(4):
        segments = [block] * repeats
        positions = [max(1, repeats // 20), repeats // 2, max(1, repeats - repeats // 20)]
        segments[positions[0]] += f"EARLY RETRIEVAL MARKER: {MARKERS['early']}\n"
        segments[positions[1]] += f"MIDDLE RETRIEVAL MARKER: {MARKERS['middle']}\n"
        segments[positions[2]] += f"LATE RETRIEVAL MARKER: {MARKERS['late']}\n"
        document = "".join(segments)
        actual = token_count(base_url, document)
        if abs(actual - target_tokens) <= 128:
            return document, actual
        repeats = max(1, int(repeats * target_tokens / max(actual, 1)))

    return document, token_count(base_url, document)


def repeated_ngram_ratio(text, n=6):
    words = text.lower().split()
    if len(words) < n * 2:
        return 0.0
    ngrams = [tuple(words[i:i + n]) for i in range(len(words) - n + 1)]
    return round(1.0 - len(set(ngrams)) / len(ngrams), 4)


def run_request(base_url, model, system_content, user_content, max_tokens):
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_content},
            {"role": "user", "content": user_content},
        ],
        "temperature": 0.0,
        "max_tokens": max_tokens,
        "stream": False,
    }
    data, wall_seconds = post_json(f"{base_url}/v1/chat/completions", payload)
    choice = data.get("choices", [{}])[0]
    message = choice.get("message", {})
    content = message.get("content", "") or message.get("reasoning_content", "") or ""
    timings = data.get("timings", {})
    found = {name: marker in content for name, marker in MARKERS.items()}
    return {
        "wall_seconds": round(wall_seconds, 3),
        "prompt_tokens": timings.get("prompt_n"),
        "prompt_ms": timings.get("prompt_ms"),
        "prompt_tps": timings.get("prompt_per_second"),
        "completion_tokens": timings.get("predicted_n"),
        "decode_tps": timings.get("predicted_per_second"),
        "finish_reason": choice.get("finish_reason"),
        "markers_found": found,
        "all_markers_found": all(found.values()),
        "repeated_6gram_ratio": repeated_ngram_ratio(content),
        "content": content,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18081)
    parser.add_argument("--model", default="qwen38-27b")
    parser.add_argument("--depths", type=int, nargs="+", default=DEFAULT_DEPTHS)
    parser.add_argument("--allow-extreme-context", action="store_true", help="Allow targets above 64K; may hang or reboot the host")
    parser.add_argument("--export-dir", default=str(ROOT_DIR / "benchmarks"))
    args = parser.parse_args()

    if max(args.depths) > 65536 and not args.allow_extreme_context:
        parser.error("targets above 64K require --allow-extreme-context due observed host instability")

    base_url = f"http://{args.host}:{args.port}"
    with urllib.request.urlopen(f"{base_url}/health", timeout=10):
        pass

    results = []
    for target in args.depths:
        print(f"Building approximately {target:,} tokenizer tokens...", flush=True)
        document, document_tokens = build_document(base_url, target)
        print(f"Document tokens: {document_tokens:,}; running cold retrieval...", flush=True)
        cold = run_request(
            base_url,
            args.model,
            document,
            "Return only the three retrieval marker values in early, middle, late order.",
            96,
        )
        print(f"Cold prompt: {cold['prompt_ms']} ms; running cached retrieval...", flush=True)
        cached = run_request(
            base_url,
            args.model,
            document,
            "List the exact early, middle, and late retrieval marker values. Do not explain.",
            96,
        )
        print(f"Cached prompt: {cached['prompt_ms']} ms; checking longer output...", flush=True)
        quality = run_request(
            base_url,
            args.model,
            document,
            "Write five concise, non-repetitive bullet points explaining what this document tests, then list all three exact marker values once.",
            384,
        )
        speedup = None
        if cold.get("prompt_ms") and cached.get("prompt_ms"):
            speedup = round(cold["prompt_ms"] / cached["prompt_ms"], 2)
        results.append({
            "target_tokens": target,
            "document_tokens": document_tokens,
            "cold": cold,
            "cached": cached,
            "quality": quality,
            "cache_prefill_speedup": speedup,
        })

    output_dir = Path(args.export_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output = output_dir / f"long_context_cache_{timestamp}.json"
    output.write_text(json.dumps({
        "timestamp": datetime.now().isoformat(),
        "server": base_url,
        "model": args.model,
        "markers": MARKERS,
        "results": results,
    }, indent=2))
    print(f"Results saved to {output}")


if __name__ == "__main__":
    main()
