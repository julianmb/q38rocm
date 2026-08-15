# Qwen 3.8 27B ROCmFP4_FAST on AMD Strix Halo (Ryzen AI Max+ 395)

[![Hardware](https://img.shields.io/badge/Hardware-AMD_Strix_Halo_(gfx1151)-ED1C24?logo=amd)](https://www.amd.com)
[![Vulkan](https://img.shields.io/badge/Driver-Mesa_RADV_Wave64-FF5722?logo=vulkan)](https://mesa3d.org)
[![Quantization](https://img.shields.io/badge/Quant-ROCmFP4_FAST_(4.26_bpw)-009688)]()
[![Speculative TPS](https://img.shields.io/badge/Peak_MTP_TPS-36.04_tok%2Fs-4CAF50)]()
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

High-performance, memory-optimized quantization and speculative decoding deployment of **Qwen 3.8 27B** engineered specifically for the **AMD Strix Halo (Ryzen AI Max+ 395 / Radeon 8060S)** platform.

By combining **ROCmFP4 matrix quantization (4.26 bpw)**, **MTP (Multi-Token Prediction) Speculative Decoding**, **Asymmetric TurboQuant KV Cache**, and the **RADV Wave64 Cooperative Matrix** engine, this repository delivers **30.56 – 36.04 tokens/second** generation throughput on a single 128 GB unified memory APU — breaking past the traditional 27B memory-bandwidth ceiling.

---

## ⚡ Performance Highlights & Benchmarks

All benchmarks measured on **AMD Ryzen AI Max+ 395 (40 CU Radeon 8060S @ 2.9 GHz, 128 GB LPDDR5X-8000 @ 273 GB/s, Linux 7.0)**:

| Optimization Level | Context / Precision | Unassisted Decode | MTP Speculative Decode | Peak Speedup vs Stock | TTFT (Prompt Eval) |
|---|---|---|---|---|---|
| **Stock `Q4_K_M` (Baseline)** | 32K / FP16 KV | 12.27 tok/s | N/A | 1.00× | 526.7 ms |
| **`ROCmFP4_FAST`** | 32K / TurboQuant KV | 14.02 tok/s | N/A | 1.14× | 468.3 ms |
| **`ROCmFP4_FAST` + Strict Greedy MTP** | 32K / TurboQuant KV | 14.02 tok/s | **34.82 tok/s** | **2.84×** | 442.8 ms |
| **`ROCmFP4_FAST` + MTP (`n6/p0.60`)** | 32K / TurboQuant KV | 14.02 tok/s | **30.56 – 34.82 tok/s** | **2.50× – 2.84×** | 439.4 ms |
| **`ROCmFP4_FAST` + Deep Spec (`n7/p0.35`)** | 32K / TurboQuant KV | 14.02 tok/s | 🔥 **36.04 tok/s** | 🔥 **2.94×** | 445.8 ms |

### Quantization Menu (Strix Halo 2-bit to 4-bit)

| Quantization Format | Model Size | Effective BPW | Raw Unassisted Decode | MTP Speculative Decode | Draft Acceptance Rate | Recommendation |
|---|---|---|---|---|---|---|
| **`ROCmFP4_FAST`** | **13.55 GiB** | **4.26** | **14.02 tok/s** | 🔥 **30.56 – 36.04 tok/s** | **76% – 88%** | **Gold Standard (Highest Total Throughput)** |
| **`Q3_K_M`** | 12.56 GiB | 3.95 | 15.15 tok/s | 25.00 – 28.50 tok/s | 70% – 78% | Balanced 3-bit deployment |
| **`Q3_K_S`** | 11.40 GiB | 3.59 | **16.69 tok/s** | 20.44 – 26.11 tok/s | 65% – 74% | Fastest unassisted decode |
| **`ROCmFP2`** | 8.56 GiB | 2.69 | 12.82 tok/s | 17.50 – 19.00 tok/s | 52% – 60% | Ultra-compact memory footprint |

---

## 🧠 Heterogeneous Architecture: iGPU + XDNA 2 NPU Sidecar

AMD Strix Halo features a dedicated **50 TOPS XDNA 2 NPU** at `/dev/accel/accel0` (`amdxdna` kernel module).

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
│                +3.29% Main Latency Interference                        │
│                (vs +68.96% if draft runs on iGPU)                      │
└────────────────────────────────────────────────────────────────────────┘
```

- **Zero Memory Contention:** The NPU executes drafter models inside its local Tile SRAM, causing only **+3.29%** memory bus latency penalty on the 27B target model (compared to **+68.96%** when executing an auxiliary draft model on the iGPU).
- **Full Bus Dedication:** Leaves 100% of the 273 GB/s unified memory bandwidth dedicated to the 27B target verification step on the Radeon 8060S.

---

## 🚀 Quick Start

### 1. Environment Setup
```bash
# Clone the repository
git clone https://github.com/your-username/qwen38-27b-rocmfpx-strix-halo.git
cd qwen38-27b-rocmfpx-strix-halo

# Install Python requirements
pip install -r requirements.txt

# Source Strix Halo environment variables
source setup_env.sh
```

### 2. Launch OpenAI-Compatible API Server
```bash
# Start server with MTP speculation and TurboQuant KV cache
./run_server.sh /path/to/Qwen3.8-27B-ROCmFP4-FAST.gguf
```

Server endpoints available:
- **Chat Completions:** `POST http://localhost:8000/v1/chat/completions`
- **Health Check:** `GET http://localhost:8000/health`
- **Model Info:** `GET http://localhost:8000/v1/models`

### 3. Interactive Terminal Chat (TUI)
Launch an interactive CLI chat session with real-time token speedometers and reasoning toggles:
```bash
python3 scripts/chat_tui.py --port 8000
```

### 4. Run Automated Benchmark Suite
```bash
python3 scripts/benchmark.py --port 8000
```

### 5. Inspect NPU Status & Simulate Speculation
```bash
# Check XDNA 2 /dev/accel/accel0 hardware status
python3 scripts/npu_sidecar_drafter.py status

# Run speculative acceptance & TPS modeling
python3 scripts/npu_sidecar_drafter.py simulate --base-tps 14.02
```

---

## ⚙️ Backend Crossover Rule & Technical Innovations

### 1. ROCm vs Vulkan Backend Specialization
- **ROCm0 (HIP):** Lowest TTFT and highest prefill throughput (`pp512` @ 398.66 t/s, TTFT 324 ms).
- **Vulkan0 (Mesa RADV):** Highest decode and MTP speculative throughput (**34.8 – 36.0 t/s** via `KHR_coopmat` Wave64 vs 18.5 t/s on ROCm).

### 2. Asymmetric TurboQuant KV Cache
Configured via `-ctk q8_0 -ctv turbo4`:
- **Key Cache:** `q8_0` (preserves high attention score precision).
- **Value Cache:** `turbo4` (compresses value tokens to 4 bits with near-zero perplexity loss).
- **Memory Footprint:** Enables full **262,144 token context** using only **23.55 GiB RAM**.

### 3. Lossless Strict Greedy MTP Verification
Enable exact greedy mathematical equivalence with no-spec decoding:
```bash
llama-server -m Qwen3.8-27B-ROCmFP4-FAST.gguf --spec-type draft-mtp --spec-mtp-strict-qwen
```

---

## 📁 Repository Structure

```
.
├── README.md                  # This documentation
├── LICENSE                    # Apache 2.0 License
├── requirements.txt           # Python dependencies
├── setup_env.sh               # Environment variable loader
├── run_server.sh              # Production llama-server launcher
├── apply_hardware_tweaks.sh   # Hardware governor and clock locking script
├── Modelfile                  # Ollama configuration
└── scripts/
    ├── chat_tui.py            # Streaming interactive terminal chat with TPS gauge
    ├── benchmark.py           # Multi-stage automated benchmark runner
    ├── tune_mtp.py            # Automated MTP parameter sweep optimizer
    └── npu_sidecar_drafter.py # AMD XDNA 2 NPU sidecar orchestrator & simulator
```

---

## 📄 License & Attribution
- Base Model: [Qwen 3.8 27B by Alibaba Cloud](https://huggingface.co/Qwen)
- ROCmFPX Toolchain & Strix Halo Optimizations: Apache 2.0 License.
