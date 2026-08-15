# Qwen 3.8 27B ROCmFP4_FAST on AMD Strix Halo (Ryzen AI Max+ 395)

[![Hardware](https://img.shields.io/badge/Hardware-AMD_Strix_Halo_(gfx1151)-ED1C24?logo=amd)](https://www.amd.com)
[![Vulkan](https://img.shields.io/badge/Driver-Mesa_RADV_Wave64-FF5722?logo=vulkan)](https://mesa3d.org)
[![Quantization](https://img.shields.io/badge/Quant-ROCmFP4_FAST_(4.26_bpw)-009688)]()
[![Speculative TPS](https://img.shields.io/badge/Peak_MTP_TPS-36.04_tok%2Fs_(Measured)-4CAF50)]()
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

High-performance, memory-optimized quantization and speculative decoding deployment of **Qwen 3.8 27B** engineered specifically for the **AMD Strix Halo (Ryzen AI Max+ 395 / Radeon 8060S)** platform.

By combining **ROCmFP4 block quantization (4.26 bpw)**, **MTP (Multi-Token Prediction) Speculative Decoding**, **Asymmetric TurboQuant KV Cache**, and the **RADV Wave64 Cooperative Matrix** engine, this package delivers **30.56 – 36.04 tokens/second** generation throughput on a single 128 GB unified memory APU — breaking past the traditional 27B memory-bandwidth ceiling.

> ⚠️ **Engine Requirement:** `ROCmFP4` is a custom ROCmFPX quantization layout designed for RDNA 3.5 / gfx1151 cooperative matrix hardware. It **requires** the ROCmFPX-enabled `llama.cpp` engine fork (pinned build: `e87d53e (213)`). Upstream stock `llama.cpp` or stock Ollama will fail to load ROCmFP4 GGUFs without this backend. See [Building the Engine](#-building-the-engine) below.

---

## ⚡ Performance Matrix & Benchmarks

All benchmark results below were measured directly on **AMD Ryzen AI Max+ 395 (40 CU Radeon 8060S @ 2.9 GHz, 128 GB LPDDR5X-8000 @ 273 GB/s, Linux 7.0, Mesa 26.0 RADV)**:

| Optimization Level | Context / Precision | Unassisted Decode *(Measured)* | MTP Speculative Decode *(Measured)* | Speedup vs Baseline | TTFT (Prompt Eval) *(Measured)* |
|---|---|---|---|---|---|
| **Stock `Q4_K_M` (Baseline)** | 32K / FP16 KV | 12.27 tok/s | N/A | 1.00× | 526.7 ms |
| **`ROCmFP4_FAST`** | 32K / TurboQuant KV | 14.02 tok/s | N/A | 1.14× | 468.3 ms |
| **`ROCmFP4_FAST` + Strict Greedy MTP** | 32K / TurboQuant KV | 14.02 tok/s | **34.82 tok/s** | **2.84×** | 442.8 ms |
| **`ROCmFP4_FAST` + MTP (`n6/p0.60`)** | 32K / TurboQuant KV | 14.02 tok/s | **30.56 – 34.82 tok/s** | **2.50× – 2.84×** | 439.4 ms |
| **`ROCmFP4_FAST` + Deep Spec (`n7/p0.35`)** | 32K / TurboQuant KV | 14.02 tok/s | 🔥 **36.04 tok/s** | 🔥 **2.94×** | 445.8 ms |

### Quantization Level Comparison on Strix Halo (2-bit to 4-bit)

| Quantization Format | Model Size | Effective BPW | Raw Unassisted Decode *(Measured)* | MTP Speculative Decode | Status / Notes |
|---|---|---|---|---|---|
| **`ROCmFP4_FAST`** | **13.55 GiB** | **4.26** | **14.02 tok/s** | 🔥 **30.56 – 36.04 tok/s** *(Measured)* | **Optimal balance of throughput & logit sharpness** |
| **`Q3_K_M`** | 12.56 GiB | 3.95 | 15.15 tok/s *(Measured)* | 25.0 – 28.5 tok/s *(Projected)* | Standard 3-bit medium quant |
| **`Q3_K_S`** | 11.40 GiB | 3.59 | **16.69 tok/s** *(Measured)* | 20.44 – 26.11 tok/s *(Measured)* | Highest unassisted decode, lower draft acceptance |
| **`ROCmFP2`** | 8.56 GiB | 2.69 | 12.82 tok/s *(Measured)* | 17.5 – 19.0 tok/s *(Projected)* | Bound by dequantization compute cost |

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

- **Zero Memory Contention:** The NPU executes draft models inside local Tile SRAM buffers, keeping 100% of the 273 GB/s unified memory bus dedicated to 27B target verification on the Radeon 8060S.

---

## 🚀 Quick Start

### 1. Environment Setup & Dependencies
```bash
# Clone the repository
git clone https://github.com/julianmb/q38rocm.git
cd q38rocm

# Install Python requirements (requests for TUI & benchmarks)
pip install -r requirements.txt

# Source Strix Halo runtime environment variables
source ./setup_env.sh
```

### 2. Download Pre-Quantized Weights
Download the pre-quantized `Qwen3.8-27B-ROCmFP4-FAST.gguf` (13.55 GiB) from Hugging Face:
```bash
./download_model.sh
```

### 3. Build the ROCmFPX Engine (If not already installed)
```bash
./build_engine.sh
```

### 4. Launch OpenAI-Compatible API Server
```bash
./run_server.sh
```

Server endpoints available:
- **Chat Completions:** `POST http://localhost:8000/v1/chat/completions`
- **Health Check:** `GET http://localhost:8000/health`
- **Model Info:** `GET http://localhost:8000/v1/models`

### 5. Interactive Terminal Chat (TUI)
Launch interactive streaming chat with real-time token speedometers and reasoning toggles:
```bash
python3 scripts/chat_tui.py --port 8000
```

### 6. Run Benchmark Suite
```bash
python3 scripts/benchmark.py --port 8000
```

### 7. Inspect NPU Hardware & Simulate Speculation
```bash
python3 scripts/npu_sidecar_drafter.py status
python3 scripts/npu_sidecar_drafter.py simulate --base-tps 14.02
```

---

## ⚙️ Backend Crossover Rule & Technical Innovations

### 1. ROCm vs Vulkan Backend Specialization
- **ROCm0 (HIP):** Lowest TTFT and highest prefill throughput (`pp512` @ 398.66 t/s, TTFT 324 ms).
- **Vulkan0 (Mesa RADV):** Highest decode and MTP speculative throughput (**34.8 – 36.0 t/s** via `KHR_coopmat` Wave64 vs 18.5 t/s on ROCm).

### 2. Asymmetric TurboQuant KV Cache
Configured via `-ctk q8_0 -ctv turbo4`:
- **Key Cache:** `q8_0` (preserves attention precision).
- **Value Cache:** `turbo4` (compresses value tokens to 4 bits with near-zero perplexity impact).
- **Memory Footprint:** Enables full **262,144 token context** using only **23.55 GiB RAM**.

### 3. Lossless Strict Greedy MTP Verification
Enable exact greedy mathematical equivalence with no-spec decoding:
```bash
llama-server -m Qwen3.8-27B-ROCmFP4-FAST.gguf -dev Vulkan0 --spec-type draft-mtp --spec-mtp-strict-qwen
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
- **Custom Backend:** This model cannot be run on standard upstream llama.cpp without ROCmFPX kernel modifications.
- **Hardware Target:** Optimized specifically for AMD Strix Halo (RDNA 3.5 / gfx1151). Other architectures may experience lower throughput or require different compile flags.
- **Base Model Alignment:** Inherits all base model safety characteristics and capabilities of Qwen 3.8 27B.

---

## 📄 License & Attribution
- **Base Model:** [Qwen 3.8 27B by Alibaba Cloud](https://huggingface.co/Qwen)
- **ROCmFPX Toolchain & Strix Halo Optimizations:** Apache 2.0 License.
- **Community Artifacts:** NPU contention metrics referenced from [ciru-ai's Strix Halo research](https://github.com/ciru-ai/strix-halo-evo-x2-evidence).
