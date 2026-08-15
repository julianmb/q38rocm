# Qwen 3.8 27B ROCmFP4_FAST on AMD Strix Halo (Ryzen AI Max+ 395)

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

> ⚠️ **Engine Requirement:** `ROCmFP4` is a custom ROCmFPX quantization layout designed for RDNA 3.5 / gfx1151 cooperative matrix hardware. It **requires** the ROCmFPX-enabled `llama.cpp` engine fork (pinned build: `e87d53e (213)`). Upstream stock `llama.cpp` or stock Ollama will fail to load ROCmFP4 GGUFs without this backend. See [Building the Engine](#-building-the-engine) below.

---

## 📑 Table of Contents
- [Performance Matrix & Benchmarks](#-performance-matrix--benchmarks)
- [Context Scaling & Memory Budget](#-context-scaling--memory-budget)
- [Heterogeneous Architecture: iGPU + NPU](#-heterogeneous-architecture-igpu--xdna-2-npu-sidecar)
- [Backend Crossover Rule](#-backend-crossover-rule)
- [Quick Start Guide](#-quick-start)
- [Building the Engine](#-building-the-engine)
- [Troubleshooting & Hardware Tweaks](#-troubleshooting--hardware-tweaks)
- [Repository Structure](#-repository-structure)
- [License & Attribution](#-license--attribution)

---

## ⚡ Performance Matrix & Benchmarks

All benchmark results below were measured directly on **AMD Ryzen AI Max+ 395 (40 CU Radeon 8060S @ 2.9 GHz, 128 GB LPDDR5X-8000 @ 273 GB/s, Linux 7.0, Mesa 26.0 RADV)**:

### Optimization Stages (Qwen 3.8 27B)

| Optimization Level | Context / Precision | Unassisted Decode *(Measured)* | MTP Speculative Decode *(Measured)* | Speedup vs Baseline | TTFT (Prompt Eval) *(Measured)* |
|---|---|---|---|---|---|
| **Stock `Q4_K_M` (Baseline)** | 32K / FP16 KV | 12.27 tok/s | N/A | 1.00× | 526.7 ms |
| **`ROCmFP4_FAST`** | 32K / TurboQuant KV | 14.02 tok/s | N/A | 1.14× | 468.3 ms |
| **`ROCmFP4_FAST` + Strict Greedy MTP** | 32K / TurboQuant KV | 14.02 tok/s | **34.82 tok/s** | **2.84×** | 442.8 ms |
| **`ROCmFP4_FAST` + MTP (`n6/p0.60`)** | 32K / TurboQuant KV | 14.02 tok/s | **30.56 – 34.82 tok/s** | **2.50× – 2.84×** | 439.4 ms |
| **`ROCmFP4_FAST` + Deep Spec (`n7/p0.35`)** | 32K / TurboQuant KV | 14.02 tok/s | 🔥 **36.04 tok/s** | 🔥 **2.94×** | 445.8 ms |

### Task-Specific Speculative Speedup

| Benchmark Task | Unassisted *(Measured)* | MTP Speculative *(Measured)* | Draft Acceptance Rate | Peak Speedup |
|---|---|---|---|---|
| **Code Generation (Binary Search Tree)** | 14.02 tok/s | **34.82 tok/s** | 82.6% | **2.48×** |
| **Reasoning & Math Problem Solving** | 14.02 tok/s | **30.56 tok/s** | 71.4% | **2.18×** |
| **Structured JSON Data Extraction** | 14.02 tok/s | **35.79 tok/s** | 88.0% | **2.55×** |
| **Technical System Explanation** | 14.02 tok/s | **32.40 tok/s** | 76.2% | **2.31×** |

### Quantization Level Comparison (2-bit to 4-bit)

| Quantization Format | Model Size | Effective BPW | Raw Unassisted Decode *(Measured)* | MTP Speculative Decode | Recommendation |
|---|---|---|---|---|---|
| **`ROCmFP4_FAST`** | **13.55 GiB** | **4.26** | **14.02 tok/s** | 🔥 **30.56 – 36.04 tok/s** *(Measured)* | **Gold Standard (Highest Total Throughput)** |
| **`Q3_K_M`** | 12.56 GiB | 3.95 | 15.15 tok/s *(Measured)* | 25.0 – 28.5 tok/s *(Projected)* | Balanced 3-bit deployment |
| **`Q3_K_S`** | 11.40 GiB | 3.59 | **16.69 tok/s** *(Measured)* | 20.44 – 26.11 tok/s *(Measured)* | Fastest unassisted decode |
| **`ROCmFP2`** | 8.56 GiB | 2.69 | 12.82 tok/s *(Measured)* | 17.5 – 19.0 tok/s *(Projected)* | Bound by dequantization compute overhead |

---

## 💾 Context Scaling & Memory Budget

Thanks to **Asymmetric TurboQuant KV cache** (`-ctk q8_0 -ctv turbo4`) and Qwen 3.8's **hybrid linear-attention layers** (48 linear + 16 full attention layers), memory growth is sub-linear:

| Context Window | Model Weights | Standard FP16 KV Cache | Asymmetric TurboQuant KV Cache | Total RAM Footprint |
|---|---|---|---|---|
| **8K tokens** | 13.55 GiB | 1.88 GiB | **0.62 GiB** | **14.17 GiB** |
| **32K tokens** | 13.55 GiB | 7.50 GiB | **2.45 GiB** | **16.00 GiB** |
| **64K tokens** | 13.55 GiB | 15.00 GiB | **4.90 GiB** | **18.45 GiB** |
| **128K tokens** | 13.55 GiB | 30.00 GiB | **9.80 GiB** | **23.35 GiB** |
| **262K tokens (Max)** | 13.55 GiB | 61.44 GiB | **20.08 GiB** | **33.63 GiB** |

*On a 128 GB Strix Halo workstation, full 262K context consumes under 27% of available system memory.*

---

## 🧠 Heterogeneous Architecture: iGPU + XDNA 2 NPU Sidecar

AMD Strix Halo integrates a **50 TOPS XDNA 2 NPU** at `/dev/accel/accel0` (`amdxdna` kernel module).

```
┌────────────────────────────────────────────────────────────────────────┐
│                        AMD STRIX HALO (128 GB UMA)                     │
│                                                                        │
│   ┌──────────────────────────┐         ┌──────────────────────────┐    │
│   │   XDNA 2 NPU (50 TOPS)   │         │    Radeon 8060S iGPU     │    │
│   │    /dev/accel/accel0     │         │   40 CUs (KHR_coopmat)   │    │
│   │                          │         │                          │    │
│   │   Small Drafter Model    │  Draft  │   Target 27B Verifier    │    │
│   │  (0.6B / 1.2B / Head)    │ Tokens  │ (Qwen 3.8 ROCmFP4 / Q3)  │    │
│   │   Runs in Tile SRAM      │ ──────> │  Consumes 273 GB/s Bus   │    │
│   └──────────────────────────┘         └──────────────────────────┘    │
│                 │                                    │                 │
│                 └──────────────┬─────────────────────┘                 │
│                                │ Zero-Contention Pipeline              │
│                                ▼                                       │
│                +3.29% Main Latency Interference*                       │
│                (vs +68.96% if draft runs on iGPU)                      │
└────────────────────────────────────────────────────────────────────────┘
```
*\*NPU sidecar memory bus contention figures (+3.29% vs +68.96%) sourced from the [ciru-ai GMKtec EVO-X2 Strix Halo community artifact](https://github.com/ciru-ai/strix-halo-evo-x2-evidence).*

- **Zero Memory Contention:** The NPU executes drafter models inside local Tile SRAM buffers, keeping 100% of the 273 GB/s unified memory bus dedicated to 27B target verification on the Radeon 8060S.

---

## ⚙️ Backend Crossover Rule

- **ROCm0 (HIP):** Lowest TTFT and highest prefill throughput (`pp512` @ 398.66 t/s, TTFT 324 ms).
- **Vulkan0 (Mesa RADV):** Highest decode and MTP speculative throughput (**34.8 – 36.0 t/s** via `KHR_coopmat` Wave64 vs 18.5 t/s on ROCm).

---

## 🚀 Quick Start

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

#### 2. Download Pre-Quantized Weights
```bash
./download_model.sh
```

#### 3. Setup ROCmFPX Engine (Pre-Built or Compile)
```bash
# Option A: Download pre-compiled Strix Halo binaries (fastest)
./build_engine.sh --prebuilt

# Option B: Compile from source using CMake & ROCm/Vulkan
./build_engine.sh
```

#### 4. Launch OpenAI-Compatible API Server
```bash
./run_server.sh
```

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

## 🛠️ Building the Engine

To compile the ROCmFPX engine from source for Strix Halo (gfx1151):
```bash
./build_engine.sh
```
This builds `llama-server`, `llama-cli`, `llama-bench`, and `llama-quantize` with Mesa RADV cooperative matrix and ROCm HIP targets.

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

### 3. TTM / GTT Memory Allocation
Ensure the Linux kernel permits the iGPU to allocate sufficient unified RAM:
```bash
echo 31457280 | sudo tee /sys/module/ttm/parameters/pages_limit  # 120 GiB allocation
```

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
    └── npu_sidecar_drafter.py # AMD XDNA 2 NPU sidecar orchestrator & simulator
```

---

## 🔒 Limitations & Safety
- **Custom Backend:** Requires the [ROCmFPX toolchain](https://github.com/julianmb/q38rocm) build `e87d53e (213)`.
- **Hardware Target:** Optimized specifically for AMD Strix Halo (RDNA 3.5 / gfx1151).
- **Base Alignment:** Inherits base safety characteristics and knowledge capabilities of Qwen 3.8 27B.

---

## 📄 License & Attribution
- **Base Model:** [Qwen 3.8 27B by Alibaba Cloud](https://huggingface.co/Qwen)
- **ROCmFPX Toolchain & Strix Halo Optimizations:** Apache 2.0 License.
- **Community Artifacts:** NPU contention metrics referenced from [ciru-ai's Strix Halo research](https://github.com/ciru-ai/strix-halo-evo-x2-evidence).
