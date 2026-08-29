# Long-Context Scaling Benchmark Report — Qwen 3.8 27B ROCmFP4

- **Timestamp:** 2026-08-29T18:18:09.774919
- **Hardware:** AMD Ryzen AI Max+ 395 (40 CU Radeon 8060S / 128 GB UMA)
- **KV Cache Config:** Asymmetric TurboQuant (`-ctk q8_0 -ctv turbo4`)

| Target Context | Actual Prompt Tokens | TTFT (Prompt Eval) | Prefill Throughput | Decode Speed |
|---|---|---|---|---|
| **4,096** | 4,261 | 12539.09 ms | 339.82 tok/s | 27.39 tok/s |
| **32,768** | 33,549 | 127226.89 ms | 263.69 tok/s | 17.51 tok/s |
| **126,976** | 129,757 | 869553.0 ms | 149.22 tok/s | 9.65 tok/s |

---
*Generated automatically by `scripts/context_scaling_benchmark.py`.*
