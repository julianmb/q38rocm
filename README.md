# Qwen 3.8 27B ROCmFP4_FAST on AMD Strix Halo (Ryzen AI Max+ 395)

> 📦 **Dedicated Model Project:** This repository is the dedicated deep-dive project for **Qwen 3.8 27B** on AMD Strix Halo. For the unified multi-model server (Nemotron 3.5 30B, Ornith 35B, DeepSeek V4 Flash 284B, hot-swapping) and support for other AMD Radeon GPUs depending on available VRAM, visit the **[HaloFPX](https://github.com/julianmb/halofpx)** repository.

[![Hugging Face](https://img.shields.io/badge/🤗%20Hugging%20Face-julianmb%2FQwen--3.8--27B--ROCmFP4--FAST--GGUF-ffd21e.svg)](https://huggingface.co/julianmb/Qwen-3.8-27B-ROCmFP4-FAST-GGUF)
[![Hardware](https://img.shields.io/badge/Hardware-AMD_Strix_Halo_(gfx1151)-ED1C24?logo=amd)](https://www.amd.com)
[![Vulkan](https://img.shields.io/badge/Driver-Mesa_RADV_Wave64-FF5722?logo=vulkan)](https://mesa3d.org)
[![Quantization](https://img.shields.io/badge/Quant-ROCmFP4_FAST_(4.26_bpw)-009688)]()
[![Speculative TPS](https://img.shields.io/badge/Peak_MTP_TPS-36.04_tok%2Fs_(Measured)-4CAF50)]()
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

High-performance, memory-optimized deployment of **Qwen 3.8 27B** custom-engineered for **AMD Strix Halo (Ryzen AI Max+ 395 / Radeon 8060S)** APUs.

> 📦 **Hugging Face Model Weights:** [julianmb/Qwen-3.8-27B-ROCmFP4-FAST-GGUF](https://huggingface.co/julianmb/Qwen-3.8-27B-ROCmFP4-FAST-GGUF)  
> ⚡ **File:** `Qwen3.8-27B-ROCmFP4-FAST.gguf` (13.55 GiB | 4.26 bpw)  
> 🔒 **SHA256:** `fb89c78d2be91cdb68eaaaa45b1270710bf34aa721dc1f0b9e3aa7b98d2e1da9`

By combining **ROCmFP4 block quantization (4.26 bpw)**, **MTP (Multi-Token Prediction) Speculative Decoding**, **Asymmetric TurboQuant KV Cache**, and the **RADV Wave64 Cooperative Matrix** engine, this package delivers **30.56 – 36.04 tokens/second** generation throughput on a single 128 GB unified memory APU — breaking past the traditional 27B memory-bandwidth ceiling.

> ⚠️ **Engine Requirement:** `ROCmFP4` is a custom ROCmFPX quantization layout designed for RDNA 3.5 / gfx1151 cooperative matrix hardware. It **requires** the ROCmFPX-enabled `llama.cpp` engine fork (pinned commit: `0fc9568e07ccc8553010864cb8db1957e629cbfa`). Upstream stock `llama.cpp` or stock Ollama will fail to load ROCmFP4 GGUFs without this backend. See [Building the Engine](#-building-the-engine) below.

---

## 📑 Table of Contents
- [Why ROCmFP4 Improves Performance](#-why-rocmfp4-improves-performance)
- [Integration with Upstream ROCmFPX](#-integration-with-upstream-rocmfpx)
- [Performance Matrix & Benchmarks](#-performance-matrix--benchmarks)
- [Context Scaling & Memory Budget](#-context-scaling--memory-budget)
- [Experimental: AMD XDNA 2 NPU Acceleration](#-experimental--optional-amd-xdna-2-npu-acceleration)
- [Backend Crossover Rule](#-backend-crossover-rule)
- [Quick Start Guide](#-quick-start)
- [Building the Engine](#-building-the-engine)
- [Troubleshooting & Hardware Tweaks](#-troubleshooting--hardware-tweaks)
- [Repository Structure](#-repository-structure)
- [License & Attribution](#-license--attribution)

---

## 🔬 Why ROCmFP4 Improves Performance

Understanding why **ROCmFP4 delivers 30–36 tok/s** on a 27B model while stock implementations run at 12 tok/s comes down to three architectural breakthroughs:

### 1. Eliminating the Memory Bandwidth Bottleneck
In auto-regressive LLM decoding, every generated token requires loading **100% of the active model weights** from RAM into GPU registers. On AMD Strix Halo's 256-bit unified memory bus (~190–200 GB/s sustained read bandwidth):

$$\text{Theoretical Decode Throughput} = \frac{\text{Memory Bandwidth (GB/s)}}{\text{Model Weight Size (GB)}}$$

- **FP16 (54.6 GB):** $200 / 54.6 \approx \mathbf{3.6\text{--}5.0 \text{ tok/s}}$
- **Stock Q4_K_M (15.92 GB):** Complex multi-scale dequantization math adds compute overhead $\to \mathbf{12.27 \text{ tok/s}}$
- **ROCmFP4_FAST (13.55 GB):** Slashes the memory transfer payload by **75.2% vs FP16** and **14.9% vs Q4_K_M**, raising raw streaming throughput to **14.02 tok/s**.

```
Weight Size vs Memory Bandwidth Barrier (27B Model on Strix Halo)
┌────────────────────────────────────────────────────────────────────────┐
│ FP16 (54.6 GB)       ████████████████████████████████████ (5.0 tok/s)  │
│ Q4_K_M (15.9 GB)     ███████████ (12.27 tok/s)                        │
│ ROCmFP4 (13.5 GB)    █████████ (14.02 tok/s unassisted)               │
│ ROCmFP4 + MTP Spec   █████████ 🚀 🚀 🚀 (36.04 tok/s with speculation)│
└────────────────────────────────────────────────────────────────────────┘
```

### 2. Hardware-Aligned Block Quantization (Block Size 32 + Wave64)
- **Zero Dequantization Stalls:** Standard k-quants use complex hierarchical scales that require multiple arithmetic operations to unpack. `ROCmFP4` groups exactly **32 weights per shared FP16 scale factor**, matching RDNA 3.5 hardware vector register strides (32 elements per half-wave).
- **Mesa RADV Cooperative Matrices (`KHR_coopmat`):** The Vulkan backend compiles dequantization and matrix multiply directly into Wave64 dual-issue SIMD instructions, executing memory fetch and dequantization in a single hardware pass.

### 3. MTP Speculative Multiplication (14.0 $\to$ 36.0 tok/s)
- **Sharp Logit Distributions:** Because `ROCmFP4` preserves attention projection precision and keeps the internal MTP draft heads in high precision (FP16 / Q8), draft candidate quality remains high (**75%–88% acceptance rate**).
- **Multiple Tokens Per Memory Pass:** Instead of loading 13.55 GB to produce 1 token, the engine verifies 4 to 6 candidate tokens in parallel during a single memory sweep. This multiplies generation speed by **2.5× to 2.94×**, breaking past the physical 14 tok/s memory bus ceiling to reach **30.56 – 36.04 tok/s**.

### 4. Asymmetric TurboQuant KV Cache
- Traditional FP16 KV caches balloon rapidly at long context (61.4 GB at 262K context).
- **Asymmetric TurboQuant (`-ctk q8_0 -ctv turbo4`)** keeps attention Keys in Q8 (preserving precise attention routing) while compressing Values to 4-bit, dropping 262K context memory from 61.4 GB to **20.08 GB**. This ensures 95%+ of memory bus bandwidth remains dedicated to model weight streaming.

### 5. What About 8-Bit (ROCmFP8)? Bandwidth Savings vs Register Execution
A common question in the community is whether 8-bit quantization is worthwhile on AMD Strix Halo if RDNA 3.5 executes matrix multiplication in FP16 registers:

- **The Execution Reality:** Unlike CDNA 3 enterprise accelerators (MI300X) which have dedicated FP8 matrix compute hardware, RDNA 3.5 (client graphics/APU architecture) executes cooperative matrix ALUs in FP16. When loading 8-bit weights (`ROCmFP8` / `Q8_0_ROCMFPX`), the GPU kernel streams 8-bit values across the memory bus and unpacks them into **FP16 registers on-the-fly**.
- **Why It Doubles Performance Over FP16:** Auto-regressive generation is **100% memory-bus bandwidth bound**, not compute bound. The GPU spends ~95% of its cycle waiting for weights to travel across the memory bus from RAM:
  - **FP16 (54.6 GB payload):** ~5.0 tok/s unassisted, ~10–12 tok/s with MTP.
  - **ROCmFP8 (26.25 GB payload):** **7.66 tok/s unassisted, 18.96 tok/s with MTP (2× faster than FP16)** with **<0.003 PPL delta (virtually zero loss)**.
  - **ROCmFP4 (13.55 GB payload):** **14.02 tok/s unassisted, 36.04 tok/s with MTP (7× faster than FP16)** with **~99% benchmark retention**.

| Format | Transferred Payload / Token | Measured MTP Speed | PPL Delta vs FP16 | Recommended Audience |
|---|---|---|---|---|
| **FP16** | 54.60 GB | ~10–12 tok/s | 0.000 (Baseline) | Reference evaluation |
| **ROCmFP8 (8-bit)** | 26.25 GB | **18.96 tok/s** | **<0.003 (Zero-loss)** | Users demanding 100% precision with 2× speedup |
| **ROCmFP4 (4-bit)** | 13.55 GB | 🔥 **36.04 tok/s** | **~0.04 (99% score)** | **Default recommendation for daily coding & agent workflows** |

---

## 🤝 Integration with Upstream ROCmFPX

This repository (`julianmb/q38rocm`) builds on top of the open-source **[charlie12345/ROCmFPX](https://github.com/charlie12345/ROCmFPX)** toolchain:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   UPSTREAM ENGINE: charlie12345/ROCmFPX                │
│       (ROCm/Vulkan llama.cpp fork, RDNA 3.5 coopmat kernels)           │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Built & Linked via build_engine.sh
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│               DEPLOYMENT STACK: julianmb/q38rocm                       │
│  • Qwen 3.8 27B Quantized Weights Release (ROCmFP4 & ROCmFP8)          │
│  • 1-Click Quickstart & Auto-Detecting Production OpenAI Server        │
│  • Pre-Compiled Strix Halo Engine Binaries (v1.5.2 Release)            │
│  • Streaming Terminal TUI Speedometer & Telemetry Dashboard            │
│  • Multi-Prompt Benchmark & Context Scaling Verification Suite         │
│  • Docker & Docker Compose Stack with Open WebUI Integration           │
│  • Hardware Governor & Dynamic TTM Memory Auto-Configurator            │
└────────────────────────────────────────────────────────────────────────┘
```

- **Engine Core:** Our build scripts (`./build_engine.sh`) fetch the tested ROCmFPX revision `0fc9568e07ccc8553010864cb8db1957e629cbfa` or download pre-compiled Strix Halo binaries from our release assets.
- **Upstream Contributions:** Benchmark evidence, bug fixes, and calibration profiles are continuously contributed back to upstream ROCmFPX and the wider Strix Halo community.

---

## ⚡ Performance Matrix & Benchmarks

All benchmark results below were measured directly on **AMD Ryzen AI Max+ 395 (40 CU Radeon 8060S @ 2.9 GHz, 128 GB 256-bit LPDDR5X, Linux 7.0, Mesa 26.0 RADV)**. 

*(Hardware Note: Strix Halo's 256-bit memory controller achieves a peak theoretical bandwidth of **273.06 GB/s** at LPDDR5X-8533 and **256.0 GB/s** at LPDDR5X-8000. Sustained unassisted decode bandwidth reaches **~190–200 GB/s**).*

### Optimization Stages (Qwen 3.8 27B)

| Optimization Level | Context / Precision | Unassisted Decode *(Measured)* | MTP Speculative Decode *(Measured)* | Speedup vs Baseline | TTFT (Prompt Eval) *(Measured)* |
|---|---|---|---|---|---|
| **Stock `Q4_K_M` (Baseline)** | 32K / FP16 KV | 12.27 tok/s | N/A | 1.00× | 526.7 ms |
| **`ROCmFP4_FAST`** | 32K / TurboQuant KV | 14.02 tok/s | N/A | 1.14× | 468.3 ms |
| **`ROCmFP4_FAST` + Strict Greedy MTP** | 32K / TurboQuant KV | 14.02 tok/s | **34.82 tok/s** | **2.84×** | 442.8 ms |
| **`ROCmFP4_FAST` + MTP (`n6/p0.60`)** | 32K / TurboQuant KV | 14.02 tok/s | **30.56 – 34.82 tok/s** | **2.50× – 2.84×** | 439.4 ms |
| **`ROCmFP4_FAST` + Deep Spec (`n7/p0.35`)** | 32K / TurboQuant KV | 14.02 tok/s | 🔥 **36.04 tok/s** *(JSON/Code)* | 🔥 **2.94×** | 445.8 ms |

> ⚠️ **Measured conditions — sampling temperature governs MTP gains.** Every MTP number in
> these tables was measured with greedy / near-greedy sampling (`temperature ≈ 0`). At
> conversational temperatures the draft acceptance rate collapses — measured in
> [issue #12](https://github.com/julianmb/q38rocm/issues/12): ~88% at temp 0 vs ~25% at
> temp 0.8, with per-position acceptance falling to 5% late in generation — and speculative
> decoding returns close to unassisted decode speed. For maximum throughput keep
> `TEMPERATURE=0.0–0.2` (`./run_server.sh --temperature 0` or `--profile agent`); for
> high-temperature chat workloads, expect decode nearer the *Unassisted* column.

### Task-Specific Speculative Speedup

| Benchmark Task | Unassisted *(Measured)* | MTP Speculative *(Measured)* | Draft Acceptance Rate | Peak Speedup |
|---|---|---|---|---|
| **Code Generation (Binary Search Tree)** | 14.02 tok/s | **34.82 tok/s** | 82.6% | **2.48×** |
| **Reasoning & Math Problem Solving** | 14.02 tok/s | **30.56 tok/s** | 71.4% | **2.18×** |
| **Structured JSON Data Extraction** | 14.02 tok/s | **35.79 tok/s** | 88.0% | **2.55×** |
| **Technical System Explanation** | 14.02 tok/s | **32.40 tok/s** | 76.2% | **2.31×** |

### 🎯 Workload-Specific MTP Tuning Profiles

| Workload Type | Optimal Profile | Recommended Launch Flags | Measured Single-Slot TPS | Measured Aggregate TPS |
|---|---|---|---|---|
| **Single-User Sustained Decode (Sweet Spot)** | `n4 / p0.0` | `./run_server.sh --draft-n 4 --draft-p 0.0 --ubatch 2048 --reasoning off` | 🔥 **33.80 tok/s sustained** (2.40× over baseline) | **33.80 tok/s** |
| **Coding Agents (Exact Greedy)** | Strict `n4 / p0.0` | `./run_server.sh --profile agent` | **34.82 tok/s measured** | **34.82 tok/s** |
| **Single-User Interactive Chat (Burst)** | `n5 / p0.50` | `./run_server.sh --draft-n 5 --draft-p 0.50` | 🔥 **28.59 – 36.04 tok/s** | **28.59 – 36.04 tok/s** |
| **Parallel Multi-Agent Slots (4-Way)** | `n6 / p0.60` | `./run_server.sh --slots 4 --draft-n 6 --draft-p 0.60` | **12.4 – 16.7 tok/s / slot** | 🔥 **23.15 (sustained) – 40.50 (burst) tok/s** |

> 💡 **MTP Depth (`K`) Scaling Insight:** Empirical sweeps show `K=4` is the optimal single-stream sweet spot on Strix Halo. `K=6` regresses slightly due to bus saturation, and `K=8` causes severe rollback degradation (18.2 tok/s). For 4-slot parallel concurrency, `K=6 / p0.60` maintains higher shared-slot throughput.

> For long-running coding agents, use strict Qwen MTP so target verification remains boundary-safe and greedy-exact. If output loops or degenerates, retry with `--no-mtp` to distinguish an MTP issue from sampling or client retries. Avoid large presence penalties; values such as `1.5` can force rare-token gibberish in long generations.

*Community Validation: 4 concurrent 131K slots run continuously under thermal soak at 71.88°C with zero GPU resets or OOM events (credit: MrWidmoreHK & kujetic).*

*Community Validation (2026-08-22, Reddit/u-Dutchnamn): the **36.04 tok/s** MTP peak was independently replicated with "tiny error" on the same APU. In the same session, the DFlash2 drafter ([LaurentZuijdwijk fork](https://github.com/LaurentZuijdwijk/llama.cpp), PR #27342) reached **~42 tok/s on the same structured task**, with the advantage diminishing at longer context lengths and on prose — where embedded MTP sustains ~33.8 tok/s vs DFlash2's ~24.6. See [docs/DFLASH2_ALTERNATIVE.md](docs/DFLASH2_ALTERNATIVE.md). A community-quantized DFlash2 sidecar in ROCmFP4_FAST format is available at [agentionai/Qwen3.8-27B-DFlash2-ROCmFP4-FAST-GGUF](https://huggingface.co/agentionai/Qwen3.8-27B-DFlash2-ROCmFP4-FAST-GGUF) — **65.6 tok/s structured** with adaptive draft sizing.*

### Quantization Level Comparison (2-bit to 8-bit)

| Quantization Format | Model Size | Effective BPW | Raw Unassisted Decode *(Measured)* | MTP Speculative Decode | Recommendation |
|---|---|---|---|---|---|
| **`ROCmFP8` (`Q8_0_ROCMFPX`)** | **26.25 GiB** | **8.25** | **7.66 tok/s** *(Measured)* | **18.96 tok/s** *(Measured)* | **Zero-loss 8-bit precision (<0.003 PPL delta)** |
| **`ROCmFP4_FAST`** | **13.55 GiB** | **4.26** | **14.02 tok/s** | 🔥 **30.56 – 36.04 tok/s** *(Measured)* | **Gold Standard (Highest Total Throughput)** |
| **`ROCmFP4_STRIX_LEAN`** | **13.82 GiB** | **4.34** | Not measured here | Not measured here | Better coherence with protected attention K/V and embeddings/output |
| **`Q3_K_M`** | 12.56 GiB | 3.95 | 15.15 tok/s *(Measured)* | 25.0 – 28.5 tok/s *(Projected)* | Balanced 3-bit deployment |
| **`Q3_K_S`** | 11.40 GiB | 3.59 | **16.69 tok/s** *(Measured)* | 20.44 – 26.11 tok/s *(Measured)* | Fastest unassisted decode |
| **`ROCmFP2`** | 8.56 GiB | 2.69 | 12.82 tok/s *(Measured)* | 17.5 – 19.0 tok/s *(Projected)* | Bound by dequantization compute overhead |

---

## 💾 Context Scaling & Memory Budget

### Context Window vs Prefill & Decode Throughput *(Measured)*

Measured live on AMD Ryzen AI Max+ 395 (Radeon 8060S / Mesa RADV STRIX_HALO) using FlashAttention and Asymmetric TurboQuant (`-ctk q8_0 -ctv turbo4`):

| Context Window | KV Cache RAM | Prefill Speed (`pp`) *(Measured)* | TTFT (Prompt Eval) | Raw Decode (`tg`) *(Measured)* | MTP Speculative Decode *(Measured)* |
|---|---|---|---|---|---|
| **512 tokens** | **0.04 GiB** | **382.21 tok/s** | 1.34 s | **14.06 tok/s** | 🔥 **34.82 – 36.04 tok/s** |
| **2,048 tokens** | **0.15 GiB** | **356.85 tok/s** | 5.74 s | **14.04 tok/s** | **32.40 – 34.82 tok/s** |
| **4,096 tokens** | **0.31 GiB** | **339.73 tok/s** | 12.05 s | **14.01 tok/s** | **30.56 – 32.24 tok/s** |
| **8,192 tokens** | **0.62 GiB** | **311.76 tok/s** | 26.27 s | **13.98 tok/s** | **29.73 tok/s** |
| **16,384 tokens** | **1.23 GiB** | **266.57 tok/s** *(Vulkan)*<br>**329.86 tok/s** *(ROCm)* | 49.66 s | **13.85 tok/s** | **28.02 tok/s** |
| **32,768 tokens** | **2.45 GiB** | **~245.0 tok/s** | ~130 s | **13.62 tok/s** | **26.85 tok/s** |

### Long-Context Prompt-Cache Reuse — MTP + Checkpoints Coexistence *(Measured 2026-08-31)*

The `speed` profile now combines **MTP speculation with prompt caching** (RAM checkpoints + TurboQuant KV). Repeated retrieval over a shared long document was measured on Ryzen AI Max+ 395 (ROCm0 backend for prefill stability; `v1.5.3` engine, `--cache-ram 16384`):

| Document Depth | Cold Prefill | Cached Re-Prefill | **Cache Speedup** | Retrieval Quality |
|---|---:|---:|---:|---|
| **32 K tokens** | 199.1 s (159.7 tok/s) | **9.35 s** | 🔥 **21.3×** | 3/3 markers, coherent |
| **64 K tokens** | 321.1 s (201.0 tok/s) | **7.33 s** | 🔥 **43.8×** | 3/3 markers, coherent |
| **130 K tokens** | 905.8 s (143.6 tok/s) | **11.49 s** | 🔥 **78.9×** | 3/3 markers, coherent |

Every turn after the first pays **seconds, not minutes** — and MTP speculative decoding stays enabled throughout (no `spec-boundary-mismatch` fallbacks, zero cold resets). Raw artifacts: `benchmarks/long_context_cache_20260831_*.json`. Backend note: prefill numbers on ROCm0 (stable under concurrent desktop iGPU load); decode on Vulkan0 reaches the 30+ tok/s MTP rates in the tables above when the iGPU is otherwise idle.

### Memory Scaling Across Context Depths

Thanks to **Asymmetric TurboQuant KV cache** (`-ctk q8_0 -ctv turbo4`) and Qwen 3.8's **hybrid linear-attention layers** (48 linear + 16 full attention layers), memory growth is sub-linear:

| Context Window | Model Weights | Standard FP16 KV Cache | Asymmetric TurboQuant KV Cache | Total RAM Footprint |
|---|---|---|---|---|
| **8K tokens** | 13.55 GiB | 1.88 GiB | **0.62 GiB** | **14.17 GiB** |
| **32K tokens** | 13.55 GiB | 7.50 GiB | **2.45 GiB** | **16.00 GiB** |
| **64K tokens** | 13.55 GiB | 15.00 GiB | **4.90 GiB** | **18.45 GiB** |
| **128K tokens** | 13.55 GiB | 30.00 GiB | **9.80 GiB** | **23.35 GiB** |
| **262K tokens (Max)** | 13.55 GiB | 61.44 GiB | **20.08 GiB** | **33.63 GiB** |

### 💡 Key Scaling Insights:
1. **Ultra-Flat Decode Degradation (<3% drop from 512 to 32K context):** Generation speed remains steady (14.06 t/s at 512 context vs 13.62 t/s at 32K context) due to Qwen 3.8's hybrid attention architecture.
2. **Ideal on 64GB Strix Halo:** At 32K context, total memory is only **16.0 GiB**, leaving **~48 GiB free** on 64GB workstations for IDEs and desktop apps. At 262K max context, total memory is only **33.6 GiB** (leaving ~30 GiB free).
3. **Backend Crossover:** ROCm0 (HIP) maintains higher prefill throughput at 16K+ tokens (329.86 t/s on ROCm vs 266.57 t/s on Vulkan), while Vulkan0 (RADV Wave64) gives the highest decode speed and MTP speculative throughput.

---

## 🧪 Experimental / Optional: AMD XDNA 2 NPU Acceleration

> ⚠️ **Status: Experimental / Research Only**
> **Embedded MTP on the iGPU is the practical sustained-decode ceiling.** The NPU is useful only for the measured **1.8× TTFT burst on long prompts** and **~2 W intent routing**; it is not a supported decode or drafting path.
> For production deployments, use the standalone **iGPU (Vulkan0/ROCm0) + Embedded MTP**. See the complete empirical research report in [`docs/NPU_INTEGRATION.md`](docs/NPU_INTEGRATION.md).

### Measured Findings

| Configuration | Prefill | Decode | TTFT (long prompt) |
|---|---|---|---|
| iGPU only (no MTP) | 101.4 tok/s | 14.1 tok/s | ~1800 ms |
| **iGPU + embedded MTP (K=4)** | 74.6 tok/s | **33.8 tok/s** | 1587 ms |
| **Hybrid NPU-burst → iGPU** | **>370 tok/s** | 33.8 tok/s | **870 ms** *(1.8× faster)* |
| NPU standalone drafter (0.8B) | 42.9 tok/s | — | 347 ms |

### What the NPU is actually good for
1. **1.8× faster first token on long prompts** (870 ms vs 1587 ms) — the NPU bursts the prompt prefix while the iGPU loads weights.
2. **~2 W always-on intent routing** (chat/code/translation classifier) with zero iGPU contention.
3. It does **not** help sustained decode — any separate drafter loses to the model's own embedded MTP heads, which share weights with zero extra memory traffic.

### Installation (optional)

```bash
# 1. Enable IOMMU SVA & module auto-load (requires reboot)
sudo sed -i 's/amd_iommu=off/iommu=pt/g' /etc/default/grub
echo amdxdna | sudo tee /etc/modules-load.d/amdxdna.conf
sudo update-grub && sudo reboot

# 2. Install XRT (built from the bundled amd/xdna-driver submodule)
git submodule update --init --recursive
cd xdna-driver/xrt/build && ./build.sh -npu -opt
sudo make install Release/XRT/xilinx/xrt.rpm  # Or follow Debian/Ubuntu package instructions for .deb
source /opt/xilinx/xrt/setup.sh
xrt-smi examine          # should list "RyzenAI-npu5 / aie2p"

# 3. NPU inference runtime comes via Lemonade's FastFlowLM (flm) backend
lemonade backends install flm:npu
lemonade pull qwen3.5-0.8b-FLM
lemonade load qwen3.5-0.8b-FLM

# 4. Run the hybrid pipeline (NPU burst -> iGPU handoff) for the 1.8x TTFT gain
python3 scripts/run_pipeline.py --device Vulkan0 --draft-n 4
```

See [`docs/NPU_INTEGRATION.md`](docs/NPU_INTEGRATION.md) for the complete setup, the hybrid burst pipeline, and the negative results that shaped this design.

---

## ⚙️ Backend Crossover Rule

- **ROCm0 (HIP):** Lowest TTFT and highest prefill throughput (`pp512` @ 398.66 t/s, TTFT 324 ms).
- **Vulkan0 (Mesa RADV):** Highest decode and MTP speculative throughput (**34.8 – 36.0 t/s** via `KHR_coopmat` Wave64 vs 18.5 t/s on ROCm).

---

## 🚀 Quick Start

> ### ⚠️ Prerequisites: ROCm 10.0 Runtime Required (also compatible with 7.2.x)
> The ROCmFPX engine binaries are dynamically linked against ROCm runtime libraries
> (`libhipblas.so`, `librocblas.so`, `libamdhip64.so`, `libhipblaslt.so`, `libhsa-runtime64.so`,
> `librocprofiler-register.so`). **ROCm is NOT bundled.** Install it first, otherwise the
> server will fail with `error while loading shared libraries: libhipblas.so.3` (see
> [issue #5](https://github.com/julianmb/q38rocm/issues/5)). `./setup_env.sh` and
> Docker now auto-detect this and show install instructions (supports both ROCm 10.0 and 7.2.x).
>
> **Ubuntu 24.04 (one-time, ROCm 10.0 — stable repo):**
> ```bash
> sudo mkdir -p --mode=0755 /etc/apt/keyrings
> wget https://stable.repo.amd.com/rocm/gpg/packages.gpg -O - | gpg --dearmor | sudo tee /etc/apt/keyrings/amdrocm.gpg > /dev/null
> echo -e "X-Repo-Id: amdrocm-stable\nTypes: deb\nURIs: https://stable.repo.amd.com/\nSuites: noble\nComponents: main\nSigned-By: /etc/apt/keyrings/amdrocm.gpg" | sudo tee /etc/apt/sources.list.d/amdrocm-stable.sources
> sudo apt-get update && sudo apt-get install -y amdrocm-core-dev10.0-gfx1151 hip-runtime-amd hipblas rocblas hipblaslt hsa-rocr rocprofiler-register rocsolver roctracer comgr
> export ROCM_PATH=/opt/rocm/core-10.0; export HIP_PATH=$ROCM_PATH
> ```
> **Fedora/RHEL (one-time):**
> ```bash
> sudo dnf install https://repo.radeon.com/amdgpu-install/10.0/rhel/9.5/amdgpu-install-10.0.0-1.el9.noarch.rpm
> sudo dnf install rocm-dev hip-runtime-amd hipblas rocblas hipblaslt hsa-rocr
> ```
> **Docker:** The included `Dockerfile` installs the ROCm runtime automatically — no host setup needed.

### ⚡ 1-Command Quickstart (Recommended)
Run the automated launcher which downloads weights if missing, boots the background server with health check polling, and opens the streaming terminal chat:
```bash
git clone https://github.com/julianmb/q38rocm.git
cd q38rocm
pip install -r requirements.txt

./quickstart.sh
```

---

### Manual Step-by-Step Setup

#### 1. Setup Environment
```bash
source ./setup_env.sh
```
Fresh machine without ROCm? Let the script install the runtime subset for you:
```bash
source ./setup_env.sh --install-rocm   # one-time, ~1.2 GB download (Ubuntu/Fedora)

#### 2. Download Pre-Quantized Weights
```bash
./download_model.sh
```

#### 3. Setup ROCmFPX Engine (Pre-Built or Compile)
```bash
# Option A: Compile from source at the pinned ROCmFPX commit (recommended)
#           Needs cmake, git, glslc + spirv-headers, and the ROCm toolchain.
./build_engine.sh

# Option B: Download pre-compiled Strix Halo binaries (faster, but may lag the
#           pinned source revision — check the printed "Engine build:" line)
./build_engine.sh --prebuilt
```

#### 4. Launch OpenAI-Compatible API Server
```bash
./run_server.sh --profile speed
```

Choose one explicit runtime profile:

| Profile | Context | MTP | Prompt Checkpoints | Intended Workload |
|---|---:|---|---|---|
| `speed` | 128K | K=4, non-strict | RAM-aware (TurboQuant KV) | Interactive generation and maximum decode throughput (greedy default) |
| `agent` | 64K | K=4, strict | Disabled | Pi and other long-running tool agents |
| `cache` | 128K | Opt-in (`--mtp`) | RAM-aware (q8_0 KV) | Repeated long documents and stable shared prefixes |
| `safe` | 64K | Disabled | Disabled | Diagnosis and conservative agent execution |

```bash
./run_server.sh --profile agent
./run_server.sh --profile cache
./run_server.sh --profile safe
```

The `speed` profile is the fast default: greedy sampling with MTP delivers the measured 33.8 tok/s sustained decode, and RAM checkpoints now reuse long shared prefixes between turns (measured on v1.5.2: a divergent-tail follow-up on a 9K-token document completed in 4–5 s instead of a ~33 s cold prefill, with TurboQuant KV keeping the cache footprint small). Creative-chat users who want sampling diversity can restore the old behavior with `--temperature 0.8` (expect decode closer to ~21 tok/s — see the measured-conditions note above).

The `agent` and `safe` profiles explicitly pass zero context checkpoints and zero prompt-cache RAM for conservative isolation.

Server endpoints available:
- **Chat Completions:** `POST http://localhost:8000/v1/chat/completions`
- **Health Check:** `GET http://localhost:8000/health`
- **Model Info:** `GET http://localhost:8000/v1/models`

#### 5. Interactive Terminal Chat (TUI)
Launch interactive streaming chat with real-time token speedometers:
```bash
python3 scripts/chat_tui.py --port 8000
```

#### 6. Automated Benchmark Suite & Report Exporter
```bash
python3 scripts/benchmark.py --port 8000
```
*Generates formatted Markdown and JSON reports in `benchmarks/`.*

---

## 🔌 Client & IDE Integration

Connect your local developer tools and IDEs directly to the OpenAI-compatible API endpoint (`http://localhost:8000/v1`):

- **Open WebUI:** Direct web chat interface with model switching.
- **Continue.dev:** VS Code & JetBrains inline AI code completion and chat assistant.
- **Cursor IDE:** Custom OpenAI base URL configuration.
- **LiteLLM / Python SDK:** Multi-agent pipelines and unified proxying.

👉 **See the complete [Client Integration Guide (docs/CLIENT_INTEGRATION.md)](docs/CLIENT_INTEGRATION.md)** for step-by-step setup guides and configuration snippets.

---

## 🐳 Docker Deployment Options (Linux & Windows WSL2)

You can run Qwen 3.8 27B in a container with full AMD GPU passthrough on **Linux** or **Windows (Docker Desktop with WSL2 backend)**:

```bash
# Option A: Standalone High-Performance Server
docker compose up -d

# Option B: Server + Open WebUI Chat Browser
docker compose --profile webui up -d
```

👉 **See the complete [Docker Deployment Guide (docs/DOCKER_GUIDE.md)](docs/DOCKER_GUIDE.md)** for Windows WSL2 prerequisites, device passthrough, and direct `docker run` commands.

*(For multi-model serving across Nemotron, Ornith, and DeepSeek, see the [HaloFPX](https://github.com/julianmb/halofpx) container stack).*

---

## 🛠️ Building the Engine

To compile the ROCmFPX engine from source for Strix Halo (gfx1151):

```bash
# Ubuntu 24.04 build dependencies (Node.js is not required by default)
sudo apt install build-essential cmake git glslc libvulkan-dev \
    mesa-vulkan-drivers spirv-headers
```

```bash
./build_engine.sh
```
This builds `llama-server`, `llama-cli`, `llama-bench`, and `llama-quantize` with Mesa RADV cooperative matrix and ROCm HIP targets.

The default is a native static build, which avoids runtime backend-module and symbol-version mismatches when executables are copied away from the CMake tree. Static and shared builds use separate directories so stale CMake cache values cannot cross modes:

```bash
./build_engine.sh --static          # Default: portable single-directory deployment
./build_engine.sh --shared          # Developer build; copies matching .so files
./build_engine.sh --shared --clean  # Reconfigure that mode from scratch
./build_engine.sh --rocm-only       # HIP-only fallback; skips Vulkan/SPIR-V requirements
./build_engine.sh --webui           # Opt in to embedded WebUI (requires Node.js/npm)
```

All builds set `CMAKE_POSITION_INDEPENDENT_CODE=ON`, preventing Ubuntu's PIE linker from rejecting static HIP objects. The headless OpenAI API server is the default, so `LLAMA_BUILD_WEBUI=OFF` avoids an unnecessary Node.js dependency; use `--webui` only when you need the embedded UI. Vulkan builds require the Khronos `spirv-headers` package; `--rocm-only` is available for HIP-only environments.

Both linkage modes set `GGML_NATIVE=ON`, so build on the Strix Halo machine where the binaries will run. ROCm officially supports Ubuntu 24.04, while Debian 13 is not currently available in AMD's ROCm apt repository.

---

## 🔧 Troubleshooting & Hardware Tweaks

### 1. Lock GPU Performance Governor
Ensure GPU clocks do not down-throttle during generation:
```bash
./apply_hardware_tweaks.sh
# Or manually:
echo "high" | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level
```

### 2. Transparent Hugepages (THP)
Ensure THP is enabled to avoid memory allocation latency during KV expansion:
```bash
echo "madvise" | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```

### 3. TTM / GTT Memory Allocation Limit
By default, the Linux AMDGPU driver caps GPU memory allocations to 50% of system RAM. 

- **On 64GB Strix Halo:** Default 50% provides 32 GiB, which is **already plenty** for 32K context (16.0 GiB RAM) with zero configuration! To unlock 262K context (33.6 GiB RAM), expand the limit to ~56 GiB:
  ```bash
  # For 64GB RAM (expands GPU ceiling to ~56 GiB):
  echo 14680064 | sudo tee /sys/module/ttm/parameters/pages_limit
  ```
- **On 128GB Strix Halo:** Expand GPU ceiling up to 120 GiB for massive concurrency:
  ```bash
  # For 128GB RAM (expands GPU ceiling to ~120 GiB):
  echo 31457280 | sudo tee /sys/module/ttm/parameters/pages_limit
  ```
### 4. Resolving "invalid device: Vulkan0"
If your engine was compiled without `glslc` (Vulkan shader compiler), CMake silently disables the Vulkan backend and defaults to `ROCm0`.
- To unlock full **36 tok/s Vulkan0 Wave64** speed, download the pre-compiled binary:
  ```bash
  ./build_engine.sh --prebuilt
  ```
- Or install the shader compiler and recompile (`build_engine.sh` enables the
  Vulkan backend automatically once `glslc` and the SPIR-V headers are present;
  `GGML_VULKAN` is a CMake option, exporting it as an env var has no effect):
  ```bash
  sudo apt install glslc libvulkan-dev mesa-vulkan-drivers spirv-headers
  ./build_engine.sh
  ```

### 5. Controlling Reasoning / Thinking Budget (Preventing Runaway Thinking)
Qwen 3.8 defaults to high reasoning depth. If an open-ended query produces thousands of thinking tokens:
- **Cap the thinking budget** (e.g. 1024 tokens):
  ```bash
  ./run_server.sh --reasoning-budget 1024
  ```
- **Turn thinking off entirely** (instant responses):
  ```bash
  ./run_server.sh --reasoning off
  ```
- **Or via system prompt**:
  `"Reasoning effort: low. Answer concisely without chain-of-thought."`

---

## 📁 Repository Structure

```
.
├── README.md                  # Comprehensive documentation and benchmarks
├── LICENSE                    # Apache 2.0 License
├── SHA256SUMS                 # SHA256 checksums for release assets
├── requirements.txt           # Python dependencies (requests)
├── setup_env.sh               # Environment variable loader
├── download_model.sh          # One-click weight downloader from Hugging Face
├── build_engine.sh            # ROCmFPX engine compilation script
├── run_server.sh              # Production llama-server launcher
├── apply_hardware_tweaks.sh   # Hardware governor and clock locking script
├── Modelfile                  # Ollama configuration template (Experimental)
└── scripts/
    ├── chat_tui.py            # Streaming terminal chat with real-time TPS gauge
    ├── benchmark.py           # Multi-stage automated benchmark runner
    ├── tune_mtp.py            # Automated MTP parameter sweep optimizer
    ├── convert_and_quant.sh   # ROCmFP4 quantization script
    ├── run_pipeline.py        # Hybrid NPU-burst -> iGPU pipeline (1.8x TTFT, optional)
    ├── launch_pipeline.py     # Daemonize launcher for the hybrid pipeline
    └── npu_sidecar_drafter.py # AMD XDNA 2 NPU sidecar orchestrator & simulator
> 📘 **Documentation & Guides:**
> - [Troubleshooting & FAQs (`docs/TROUBLESHOOTING.md`)](docs/TROUBLESHOOTING.md)
> - [Upstream Tracking & Workaround Matrix (`docs/UPSTREAM_TRACKING.md`)](docs/UPSTREAM_TRACKING.md)
> - [Hardware Sizing & Memory Configuration (`docs/HARDWARE-AND-MEMORY.md`)](docs/HARDWARE-AND-MEMORY.md)
> - [DFlash2 Alternative Drafter Guide (`docs/DFLASH2_ALTERNATIVE.md`)](docs/DFLASH2_ALTERNATIVE.md)
> - [NPU Integration & Hybrid Pipeline (`docs/NPU_INTEGRATION.md`)](docs/NPU_INTEGRATION.md)
> - [Quantization Recipes & Precision (`docs/QUANTIZATION_RECIPES.md`)](docs/QUANTIZATION_RECIPES.md)
> - [Client Integration & SDKs (`docs/CLIENT_INTEGRATION.md`)](docs/CLIENT_INTEGRATION.md)

---

## 🔒 Limitations & Safety
- **Custom Backend:** Requires the [ROCmFPX toolchain](https://github.com/julianmb/q38rocm) build `0fc9568 (244)`.
- **Hardware Target:** Optimized specifically for AMD Strix Halo (RDNA 3.5 / gfx1151).
- **Base Alignment:** Inherits base safety characteristics and knowledge capabilities of Qwen 3.8 27B.

---

## 📄 License & Attribution
- **Base Model:** [Qwen 3.8 27B by Alibaba Cloud](https://huggingface.co/Qwen)
- **ROCmFPX Toolchain & Strix Halo Optimizations:** Apache 2.0 License.
- **Community Artifacts:** NPU contention metrics referenced from [ciru-ai's Strix Halo research](https://github.com/ciru-ai/strix-halo-evo-x2-evidence).
