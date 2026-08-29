# Long-Context Scaling Benchmark Report — Qwen 3.8 27B ROCmFP4

- **Timestamp:** 2026-08-29T18:00:58.140022
- **Hardware:** AMD Ryzen AI Max+ 395 (40 CU Radeon 8060S / 128 GB UMA)
- **KV Cache Config:** Asymmetric TurboQuant (`-ctk q8_0 -ctv turbo4`)

| Target Context | Actual Prompt Tokens | TTFT (Prompt Eval) | Prefill Throughput | Decode Speed |
|---|---|---|---|---|
| **4,096** | 4,261 | 15763.49 ms | 270.31 tok/s | 28.32 tok/s |
| **32,768** | 33,549 | 192193.47 ms | 174.56 tok/s | 17.64 tok/s |

---
*Generated automatically by `scripts/context_scaling_benchmark.py`.*
