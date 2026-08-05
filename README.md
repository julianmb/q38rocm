# 🚀 ROCmFPX Optimization Guide: Converting & Running LLMs on AMD Strix Halo (gfx1151)

Welcome to **q38rocm** — the comprehensive technical guide and reference toolkit for optimizing, quantizing, and running large language models (LLM/MoE) on **AMD Strix Halo APUs (gfx1151)** using native **ROCmFPX / ROCmFP4** tensor types.

This guide captures all engineering learnings, conversion workflows, memory profiling data, and runtime configurations tested on hardware with **AMD Ryzen AI Max+ 395 (gfx1151)** and Unified Memory Architecture (UMA).

---

## 📌 Executive Summary

Standard quantization formats (`Q4_K_M`, `Q5_K_M`, `IQ4_XS`) in upstream `llama.cpp` or Ollama are generic and not optimized for AMD's RDNA 3.5 / CDNA matrix cores on Strix Halo (`gfx1151`). 

By leveraging the experimental **`ROCmFPX` toolchain**, we convert FP8 / BF16 / standard GGUF weights into **ROCm FP4/FPX native matrix layouts**. This yields:
- **Up to 1,200+ tok/s** prompt-fill throughput (`pp512`) on 35B parameter MoE models.
- **~67.4 tok/s** generation throughput (`tg128`) on 35B models (3B active parameters).
- **Native 262K context window support** via UMA unified memory allocations.
- **Preserved agentic/coding fidelity** using tensor routing ("Coherent" and "Agent" presets) that keeps embedding and attention weights at higher precision.

---

## 🗂️ Repository Structure

```
q38rocm/
├── README.md                      # Primary overview & quick start guide
├── docs/
│   ├── QUANTIZATION-GUIDE.md      # Deep dive on FP8 -> ROCmFPX conversion & layer routing
│   ├── HARDWARE-AND-MEMORY.md     # Strix Halo UMA, BIOS memory split & context RAM formulas
│   └── BENCHMARKING-AND-PROFILING.md # llama-bench, FlashAttention & RSS tracking guide
└── scripts/
    ├── build_rocmfpx.sh           # Builds pinned charlie12345/ROCmFPX runtime for gfx1151
    ├── run_inference.sh           # Run CLI or OpenAI-compatible server with UMA flags
    └── convert_and_quant.sh       # Conversion pipeline template (FP8/BF16 -> ROCmFPX GGUF)
```

---

## 🛠️ Prerequisites & Hardware Requirements

1. **Hardware:** AMD Strix Halo APU (`gfx1151` architecture, e.g. Ryzen AI Max+ 395).
2. **System RAM:** 32GB minimum; 64GB recommended for 32K–128K context; 128GB for full 262K context.
3. **Operating System:** Linux (Ubuntu 24.04 LTS recommended, kernel 6.11+).
4. **ROCm Stack:** ROCm 7.2.x with HIP development toolchain (`hipcc`, `rocminfo`).
5. **Build Tools:** `cmake`, `git`, `g++`, `ninja` or `make`.

---

## 🚀 Quick Start

### 1. Clone & Build the ROCmFPX Runtime
```bash
git clone https://github.com/julianmb/q38rocm.git
cd q38rocm
chmod +x scripts/*.sh
./scripts/build_rocmfpx.sh
```

### 2. Run Inference
```bash
# Interactive CLI mode with Speed model (Q4_0_ROCMFP4_COHERENT)
./scripts/run_inference.sh cli speed /path/to/your-model.gguf

# OpenAI API Server on http://127.0.0.1:8080 with 32K context
./scripts/run_inference.sh server quality /path/to/your-model.gguf
```

---

## 📊 Measured Performance Highlights (35B MoE / gfx1151)

| Context | Prompt Fill (`Q4_COHERENT`) | Prompt Fill (`Q6_AGENT`) | Decode Speed |
|---:|:---:|:---:|:---:|
| **512 tokens** | **1,202.75 t/s** | **760.36 t/s** | 67.43 t/s (Q4) / 49.35 t/s (Q6) |
| **4,096 tokens** | **1,153.38 t/s** | **737.51 t/s** | ~65 t/s |
| **32,768 tokens** | **845.44 t/s** | **600.43 t/s** | ~60 t/s |
| **131,072 tokens** | **447.89 t/s** | *not tested* | ~50 t/s |
| **262,144 tokens** | **217.96 t/s** | *not tested* | ~35 t/s |

*Measured on AMD Ryzen AI Max+ 395, 124 GiB OS-visible UMA, ROCm 7.2.3, FlashAttention enabled.*

---

## 📚 Detailed Documentation

- **[Quantization Pipeline & Tensor Routing Guide](docs/QUANTIZATION-GUIDE.md)**: How ROCmFP4 and ROCmFPX work, how to preserve agent/code quality, and command-line flags for quantization.
- **[Hardware, BIOS & Memory Management Guide](docs/HARDWARE-AND-MEMORY.md)**: Setting up AGESA BIOS UMA allocations, understanding peak RSS, and system RAM compatibility matrices.
- **[Benchmarking & Performance Profiling](docs/BENCHMARKING-AND-PROFILING.md)**: Benchmarking workflows using `llama-bench`, memory measurement using `/usr/bin/time -v`, and speculative decoding / MTP status.

---

## 📄 License & Attribution

- **Guide & Scripts:** MIT License
- **ROCmFPX Fork:** [charlie12345/ROCmFPX](https://github.com/charlie12345/ROCmFPX) (MIT / llama.cpp license)
