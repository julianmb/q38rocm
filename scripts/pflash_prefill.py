#!/usr/bin/env python3
"""
pflash_prefill.py — Speculative Long-Context Prefill & Span Compression for Strix Halo
Reduces long-context (32K to 262K) Time-To-First-Token (TTFT) by selecting high-relevance prompt blocks.
"""

import sys
import json
import time
import argparse
import urllib.request

def color(text, code): return f"\033[{code}m{text}\033[0m"
def cyan(text): return color(text, "1;36")
def green(text): return color(text, "1;32")
def yellow(text): return color(text, "1;33")
def bold(text): return color(text, "1")

def chunk_text(text, chunk_size=256):
    words = text.split()
    chunks = []
    for i in range(0, len(words), chunk_size):
        chunks.append(" ".join(words[i:i + chunk_size]))
    return chunks

def score_chunks(chunks, query):
    """
    Score context chunks based on term frequency and query overlap.
    Preserves attention sinks (first chunk) and trailing instructions unconditionally.
    """
    if len(chunks) <= 2:
        return chunks

    query_terms = set(query.lower().split())
    scored = []
    
    for i, c in enumerate(chunks):
        c_terms = set(c.lower().split())
        overlap = len(query_terms.intersection(c_terms))
        # Head (sink) and Tail (trailing question context) are given maximum score
        if i == 0 or i == len(chunks) - 1:
            overlap += 1000
        scored.append((overlap, i, c))
        
    return scored

def compress_prompt(document, query, keep_ratio=0.20, min_chunks=4):
    chunks = chunk_text(document, chunk_size=200)
    if len(chunks) <= min_chunks:
        return document, len(chunks), len(chunks)
        
    num_to_keep = max(min_chunks, int(len(chunks) * keep_ratio))
    scored = score_chunks(chunks, query)
    
    # Sort by score descending and take top K
    scored.sort(key=lambda x: x[0], reverse=True)
    top_chunks = scored[:num_to_keep]
    
    # Restore original document chronological order
    top_chunks.sort(key=lambda x: x[1])
    
    compressed_text = "\n\n[...]\n\n".join([c[2] for c in top_chunks])
    return compressed_text, len(chunks), num_to_keep

def main():
    parser = argparse.ArgumentParser(description="PFlash Speculative Prefill Compressor for Strix Halo")
    parser.add_argument("--query", required=True, help="User question / prompt query")
    parser.add_argument("--file", help="Path to large document text file")
    parser.add_argument("--keep-ratio", type=float, default=0.25, help="Fraction of document spans to preserve (default: 0.25)")
    parser.add_argument("--port", type=int, default=8000, help="OpenAI server port to query")
    parser.add_argument("--host", default="127.0.0.1", help="OpenAI server host")
    args = parser.parse_args()

    document_text = ""
    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            document_text = f.read()
    else:
        document_text = sys.stdin.read()

    if not document_text.strip():
        print("Error: No document text provided.")
        sys.exit(1)

    print("\n" + "=" * 70)
    print(bold(" ⚡ PFLASH SPECULATIVE PREFILL COMPRESSOR"))
    print("=" * 70)

    start_comp = time.time()
    compressed_doc, total_c, kept_c = compress_prompt(document_text, args.query, keep_ratio=args.keep_ratio)
    comp_time = (time.time() - start_comp) * 1000

    reduction = (1 - (len(compressed_doc) / len(document_text))) * 100
    print(f"  - Original Length:   {len(document_text):,} chars ({total_c} chunks)")
    print(f"  - Compressed Length: {len(compressed_doc):,} chars ({kept_c} chunks, {green(f'-{reduction:.1f}% bandwidth')})")
    print(f"  - PFlash Scan Time:  {comp_time:.2f} ms\n")

    # Formulate final request
    full_prompt = f"Context:\n{compressed_doc}\n\nQuestion: {args.query}"
    
    print(f"[*] Sending compressed request to http://{args.host}:{args.port}/v1 ...")
    payload = json.dumps({
        "model": "strix-pflash",
        "messages": [{"role": "user", "content": full_prompt}],
        "max_tokens": 200,
        "temperature": 0
    }).encode("utf-8")
    
    req = urllib.request.Request(f"http://{args.host}:{args.port}/v1/chat/completions", data=payload, headers={"Content-Type": "application/json"})
    
    try:
        t0 = time.time()
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            elapsed = time.time() - t0
            content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
            timings = data.get("timings", {})
            ttft = timings.get("prompt_ms", 0)
            tps = timings.get("predicted_per_second", 0)
            
            print(f"\n{bold('Response:')}\n{content}\n")
            print(f"{dim('-' * 70)}")
            print(f"⏱️ TTFT: {green(f'{ttft:.1f}ms')} | Generation: {green(f'{tps:.1f} tok/s')} | Total: {elapsed:.2f}s")
            print(f"{dim('-' * 70)}\n")
    except Exception as e:
        print(f"{yellow('[Error connecting to server]')}: {e}")

if __name__ == "__main__":
    def dim(t): return f"\033[2m{t}\033[0m"
    main()
