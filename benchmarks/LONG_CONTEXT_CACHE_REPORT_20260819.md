# Long-Context Cache Validation — 2026-08-19

Hardware: AMD Ryzen AI Max+ 395, 128 GB unified memory. Engine: ROCmFPX `v215` (`12f8b7e`), Vulkan RADV.

## Valid 32K Results

| Profile | Cold Prefill | Reused-Prefix Prefill | Cache Speedup | Decode | Retrieval | Loop Check |
|---|---:|---:|---:|---:|---|---|
| MTP K=4, q8_0/q8_0 KV | 135.78 s | 135.75 s | 1.00x | 32.9–35.9 tok/s | 3/3 markers | No repeated 6-grams |
| No MTP, q8_0/q8_0 KV, 16 checkpoints | 124.31 s | 4.97 s | **25.01x** | 12.2–12.5 tok/s | 3/3 markers | No repeated 6-grams |

The longer 229-token quality response was coherent, stopped naturally, recovered all early/middle/late markers, and had a repeated 6-gram ratio of `0.0`.

## Compatibility Findings

- `cache_reuse` is disabled by this Qwen hybrid/recurrent context, even with q8_0/q8_0 KV.
- Context checkpoints work when MTP is disabled.
- MTP K=4 invalidates checkpoint restoration with `spec-boundary-mismatch`, forcing a full cold prefill.
- TurboQuant KV also disables attention rotation and cannot use cache shifting.

## ROCm Backend Comparison

| Backend | Ubatch | 128K Cold Prefill | Reused-Prefix Prefill | Decode |
|---|---:|---:|---:|---:|
| Vulkan RADV | 2048 | 845.46 s (155.06 tok/s) | 10.52 s | 10.0–10.5 tok/s |
| ROCm | 1024 | 864.82 s (151.46 tok/s) | 11.43 s | 7.4–7.5 tok/s |

ROCm was 2.3% slower on cold prefill, 8.6% slower on cached prefill, and roughly 26% slower on decode. The ubatch settings differ, so this is not a perfectly isolated backend comparison, but ROCm provided no evidence of a speed advantage. Retrieval recovered all three markers without repetition or backend errors. The longer quality response hit the 131,072-token context boundary because the prompt left only about 83 tokens for generation.

## 128K Result

| Cold Prefill | Reused-Prefix Prefill | Cache Speedup | Decode | Retrieval | Loop Check |
|---:|---:|---:|---:|---|---|
| 845.46 s (155.06 tok/s) | 10.52 s | **80.4x** | 10.0–10.5 tok/s | 3/3 markers in all responses | No repeated 6-grams |

The 251-token quality response stopped naturally, remained coherent, and recovered markers near the beginning, middle, and end of the 131K-token document.

## 192K Result

| Cold Prefill | Reused-Prefix Prefill | Cache Speedup | Decode | Retrieval | Loop Check |
|---:|---:|---:|---:|---|---|
| 1629.90 s (119.95 tok/s) | 14.55 s | **112.04x** | 9.0–9.2 tok/s | 3/3 markers in all responses | No repeated 6-grams |

The server used a 196,608-token context, no MTP, q8_0/q8_0 KV, 16 checkpoints, `-b 2048`, and the safer `-ub 1024`. The 195,473-token document produced a 195,504-token prompt. Cold retrieval, cached retrieval, and the 220-token quality response all stopped naturally and recovered the early, middle, and late markers. Memory remained stable with roughly 92 GiB available and zero swap, and no GPU or driver errors occurred.

## 224K Result

| Cold Prefill | Reused-Prefix Prefill | Cache Speedup | Decode | Retrieval | Loop Check |
|---:|---:|---:|---:|---|---|
| 2168.29 s (105.38 tok/s) | 17.57 s | **123.39x** | 8.8–9.0 tok/s | 3/3 markers in all responses | No repeated 6-grams |

The server used a 229,376-token context and the same `-ub 1024` cache profile as the 192K test. The 228,473-token document produced a 228,504-token prompt. All three responses stopped naturally and recovered every marker, including the 259-token quality response. Memory remained stable with roughly 90 GiB available and zero swap, and no GPU or driver errors occurred.

## Near-256K Stability Result

The 261K test did not complete. The first request reached 210,944 tokens before the original 30-minute client timeout. A resumed request reused the live slot and progressed to approximately 229,376 tokens before Vulkan failed:

```text
radv/amdgpu: The CS has been cancelled because the context is lost
vk::Queue::submit: ErrorDeviceLost
```

Kernel logs recorded a `comp_1.2.0` ring timeout and successful queue reset. RAM remained stable with roughly 87 GiB available and zero swap, so this was a GPU execution/driver stability failure rather than host-memory exhaustion. The failing profile used Vulkan RADV, q8_0/q8_0 KV, no MTP, and `-ub 2048`.

Raw valid artifacts:

- `long_context_cache_20260819_105210.json` — MTP K=4, q8_0/q8_0.
- `long_context_cache_20260819_105518.json` — no MTP, cache checkpoint restoration.
- `long_context_cache_20260819_112714.json` — valid 128K cache and quality result.
- `long_context_cache_20260819_125807.json` — valid 192K cache and quality result using `-ub 1024`.
- `long_context_cache_20260819_135700.json` — valid 224K cache and quality result using `-ub 1024`.
- `long_context_cache_20260819_155250.json` — ROCm 128K backend comparison.
- `long_context_cache_20260819_256k_failure.json` — 261K device-lost failure summary.
