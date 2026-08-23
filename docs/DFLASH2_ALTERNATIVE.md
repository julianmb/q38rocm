# DFlash2 as an Alternative to Embedded MTP

## TL;DR

| Workload | Recommended speculation | Measured |
|---|---|---|
| **Prose / long context** | Embedded MTP (default, `--spec-type draft-mtp`) | **~33.8 tok/s sustained** |
| **Highly structured output** (JSON, code, counting-style) | DFlash2 via the LaurentZuijdwijk fork | **~42 tok/s** (community) / **40.7** (fork author) |

Both approaches are bounded by the same hardware ceiling — the batch-8 verification
rate (~55–60 tok/s single-stream on gfx1151 with ROCmFP4). The only variable is how
well each drafter keeps that verification batch full.

---

## What DFlash2 is

[DFlash2](https://huggingface.co/incoai/Qwen3.8-27B-DFlash2-GGUF) is a separate
block-diffusion draft model for Qwen 3.8 27B (draft GGUF ≈ 1.1 GiB at Q4_K_M). It
proposes whole token blocks in parallel rather than autoregressively.

llama.cpp support ships via [PR #27342](https://github.com/ggml-org/llama.cpp/pull/27342)
(Jian Chen), carried by the community fork
[LaurentZuijdwijk/llama.cpp](https://github.com/LaurentZuijdwijk/llama.cpp) — which also
ports the ROCmFPx quant types and fixes Vulkan batched mat-vec kernels so FP4 and
speculative decoding work well *together*. It is **not** part of the stock
charlie12345/ROCmFPX engine this repository builds by default.

## When it wins — and when it doesn't

Acceptance drives everything. DFlash2's block drafting accepts near-100% on highly
predictable output, filling the verification batch; on free-form prose its acceptance
(~2.6 tokens/step) drops below what embedded MTP achieves on this model.

| Content | Engine + method | tok/s |
|---|---|---:|
| Prose (essay) | ROCmFP4_FAST + embedded MTP (K=4) | **33.8 sustained** |
| Prose (essay, temp 0) | ROCMFPX-MQ-Q4 + DFlash2 n-max 7 | 24.6 |
| Structured task | ROCmFP4_FAST + embedded MTP (deep spec) | 36.0 *(independently replicated)* |
| Same structured task | DFlash2 | **~42** |
| Counting 0–100 (ceiling probe) | DFlash2 n-max 7 | 53.0 *(88% of B=8 ceiling)* |

Sources: fork author's NOTES (2026-08-21 measurements); community replication
2026-08-22 (Reddit u/Dutchnamn).

## Trade-offs

| | Embedded MTP (default) | DFlash2 |
|---|---|---|
| Extra memory | ~none (head ships in-model) | + drafter GGUF (~1.1 GiB) + drafter KV/context |
| Extra downloads | none | drafter GGUF |
| Engine | stock ROCmFPX build (`./build_engine.sh`) | requires LaurentZuijdwijk fork |
| Prose / long context | ✅ best measured | advantage diminishes |
| Highly structured output | 36 tok/s (deep spec profile) | ✅ ~42 tok/s |

## Recipe (community-fork path)

```bash
git clone --depth 1 https://github.com/LaurentZuijdwijk/llama.cpp
cd llama.cpp
cmake -B build -DGGML_VULKAN=ON && cmake --build build -j

# The julianmb ROCmFP4 quants load on this engine unmodified:
./build/bin/llama-cli \
  -m /path/to/Qwen3.8-27B-ROCmFP4-FAST.gguf \
  -hfd incoai/Qwen3.8-27B-DFlash2-GGUF:Q4_K_M \
  --spec-type draft-dflash --spec-draft-n-max 7 -ngl 99 -fa on
```

Verified: our `Qwen3.8-27B-ROCmFP4-FAST.gguf` decodes at **13.72 ± 0.01 tok/s** bare
on that fork (parity with the stock build), so the quant is portable across both paths.

> Note (from the fork author): `--spec-draft-n-max` is content-dependent. ROCmFPx
> presets are flat between n-max 3 and 7 on prose, so 7 costs nothing there and wins
> on structured output; K-quant presets may prefer 3 on prose.
