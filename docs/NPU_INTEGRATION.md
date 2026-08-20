# NPU Integration (Optional) — AMD XDNA 2 on Strix Halo

This document is the complete reference for optionally accelerating **Qwen 3.8 27B** by combining the **AMD XDNA 2 NPU** (`/dev/accel/accel0`) with the **Radeon 8060S iGPU** (`Vulkan0` / `KHR_coopmat`).

> **Important:** NPU acceleration is **fully optional**. The server works perfectly without it. The NPU does **not** improve sustained decode speed — see the definitive findings below.

> ⚠️ **Scope note:** All NPU findings, benchmarks, and the hybrid pipeline below were **only tested on Qwen 3.8 27B** (dense, ROCmFP4_FAST).

> 🐧 **Platform note:** The entire NPU stack documented here (IOMMU SVA, XRT, FastFlowLM) is **Linux-specific and empirically validated on Linux**. **Windows users:** the same hybrid TTFT pipeline works via Lemonade's `oga` (Ryzen AI / ONNX Runtime GenAI) NPU backend — see [Section 6: Windows Support](#6-windows-support-via-lemonade-oga--ryzen-ai). WSL2 does **not** expose the XDNA NPU to guests.

| Platform | NPU Access Path | Hybrid Pipeline | Status |
|---|---|---|---|
| **Linux** (native) | `/dev/accel/accel0` + XRT + FastFlowLM (`flm:npu`) | ✅ Validated (1.8× TTFT measured) | ✅ **Reference platform** |
| **Windows 11** (native) | AMD NPU driver + Lemonade `oga` backend | ✅ Supported (same OpenAI-compatible pipeline) | ⚙️ Supported, not benchmark-validated |
| **Windows (WSL2)** | No XDMA NPU passthrough | ❌ NPU not visible in WSL2 | ❌ Not supported |

---

## 1. Hardware & System Context

| Component | Detail |
|---|---|
| Processor | AMD Ryzen AI Max+ 395 (16 Zen 5 cores) |
| iGPU | Radeon 8060S (40 CUs, RDNA 3.5, `gfx1151`) |
| NPU | AMD XDNA 2 (`RyzenAI-npu5`, 48 AIE2p tiles @ 50 TOPS, `/dev/accel/accel0`) |
| Unified Memory | 128 GB LPDDR5X-8000, 256-bit bus, ~273 GB/s peak |
| Kernel / OS | Linux 7.0 (`iommu=pt iommu.passthrough=0` SVA enabled) |
| NPU firmware | `1.1.2.65` |
| XRT | 2.26.0 at `/opt/xilinx/xrt/` |

External NPU runtimes:
- **Lemonade** (`/usr/bin/lemonade`) — local AI server (port 13305) driving the NPU via FastFlowLM.
- **FastFlowLM (`flm`)** — NPU inference runtime (v0.9.46), bundled at `/var/lib/lemonade/.cache/lemonade/bin/flm/npu/flm`.
- **XRT** (`xrt-smi`) — Xilinx Runtime for NPU management.

---

## 2. Measured Findings (empirical)

### 2.1 Performance matrix

| Architecture | Prefill | Decode | TTFT (long prompt) |
|---|---|---|---|
| Standalone iGPU (no MTP) | 101.4 tok/s | 14.1 tok/s | ~1800 ms |
| **iGPU + embedded MTP (K=4)** | 74.6 tok/s | **33.8 tok/s** | 1587 ms |
| **Hybrid NPU-burst → iGPU** | **>370 tok/s** | 33.8 tok/s | **870 ms** *(1.8× faster)* |
| EAGLE-3 full head | — | 19.8 tok/s | — |
| EAGLE-3 compressed head | — | 12.4 tok/s | — |

### 2.2 NPU drafter (measured)

- `qwen3.5-0.8b-FLM`: **42.9 tok/s**, **347 ms TTFT**, **~2 W**, 0.2 GB footprint.

### 2.3 The Definitive Answer

**33.8 tok/s via embedded MTP (iGPU only) is the practical ceiling on Strix Halo.**

The NPU's real, proven value:
1. **1.8× faster first token on long prompts** (870 ms vs 1587 ms) via the hybrid burst pipeline.
2. **~2 W always-on intent routing** (chat/code/translation classifier) with zero iGPU contention.
3. It does **not** improve sustained decode speed — any separate drafter loses to the model's own embedded MTP heads (which share the target's weights with zero auxiliary memory traffic).

### 2.4 Negative results (documented)

- NPU as co-decoder: the NPU's 42.9 tok/s degrades to ~14 tok/s under shared-bus contention.
- Split-device MTP head (CPU/GPU): 16.9–22.7 tok/s — loses to embedded 33.8.
- EAGLE-3 compressed head: 7.4% acceptance — its 32k draft vocab covers only 18.5k/248k tokens.

---

## 3. Installation (optional)

### 3.1 Enable IOMMU SVA (required, needs reboot)

The NPU requires IOMMU Shared Virtual Addressing. Check your boot flags:
```bash
cat /proc/cmdline
# Must include: iommu=pt iommu.passthrough=0
```

If missing, update GRUB and reboot:
```bash
sudo sed -i 's/amd_iommu=off/iommu=pt iommu.passthrough=0/g' /etc/default/grub
sudo update-grub
sudo reboot
```

### 3.2 Install XRT (user-space runtime)

XRT is built from the AMD XDNA driver source (bundled as the `xdna-driver/` git submodule in this repo):
```bash
git submodule update --init --recursive
cd xdna-driver/xrt/build
./build.sh -npu -opt -j 16 -noert -disable-werror
cd Release && sudo make install
```

### 3.3 Verify the NPU

```bash
source /opt/xilinx/xrt/setup.sh
xrt-smi examine
```

Expected output:
```
Device(s) Present
|BDF             |Name          |Architecture  |Topology  |
|----------------|--------------|--------------|----------|
|[0000:c7:00.1]  |RyzenAI-npu5  |aie2p         |6x8       |
```

Verify SVA access from user space:
```bash
python3 -c 'import os; fd = os.open("/dev/accel/accel0", os.O_RDWR); print("OK", fd)'
```

### 3.4 NPU inference runtime (Lemonade / FastFlowLM)

```bash
# Check the flm:npu backend status
lemonade backends --all
# Install the FastFlowLM NPU backend if needed
lemonade backends install flm:npu
```

### 3.5 Pull & load the NPU drafter model

```bash
# Pull the 0.8B NPU drafter (small, ~0.2 GB)
lemonade pull qwen3.5-0.8b-FLM

# Load it onto the NPU
lemonade load qwen3.5-0.8b-FLM
# -> "Model loaded successfully!"
```

---

## 4. Getting the TTFT Speedup — Run the Hybrid Pipeline

The hybrid pipeline streams the **first ~24 tokens from the NPU** and then asks the 27B iGPU model to continue that prefix. This is a latency/quality tradeoff, not speculative verification: tokens already sent to the client cannot be corrected by the target model. Use the normal iGPU-only endpoint for strict structured output, tool calls, or other correctness-sensitive requests.

### 4.1 Prerequisites
- Qwen 3.8 27B weights downloaded (`./download_model.sh`).
- ROCmFPX engine built (`./build_engine.sh`).
- NPU set up per section 3 (IOMMU, XRT, Lemonade + `qwen3.5-0.8b-FLM` loaded).

### 4.2 Install the pipeline dependency
```bash
pip install -r requirements.txt   # adds aiohttp
```

### 4.3 Launch the hybrid pipeline
```bash
# Foreground (recommended for first run — watch the logs)
python3 scripts/run_pipeline.py --device Vulkan0 --draft-n 4

# Or daemonize (double-fork, logs to /tmp/pipeline.log)
python3 scripts/launch_pipeline.py --device Vulkan0 --draft-n 4
```

This starts an OpenAI-compatible endpoint on **port 11435**:
- It launches the iGPU server (Qwen 3.8 ROCmFP4 + embedded MTP K=4) on port 8012.
- It probes Lemonade for the NPU drafter. If the NPU is available, requests get the **NPU burst → iGPU handoff** path.

### 4.4 Verify the TTFT improvement

```bash
# Health check (confirms NPU is on)
curl http://127.0.0.1:11435/health
# -> "npu_available": true

# Measure TTFT with the hybrid pipeline
curl -s http://127.0.0.1:11435/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Write a long technical explanation of IOMMU SVA."}],"stream":true}'

# Compare against iGPU-only (baseline ~1587 ms long-prompt TTFT)
./run_server.sh
```

**Expected result:** the first token arrives in **~870 ms** (vs ~1587 ms iGPU-only) — a **1.8× first-token speedup** on long prompts. Sustained decode stays at 33.8 tok/s (the NPU does not help there).

---

## 5. Related research workspace

The full empirical study lives in `/home/user/source/npuhalo/`:
- `docs/REPORT.md` — full technical report (tools, code, paths, findings).
- `docs/final_verdict.md` — reconciled verdict and forward-path assessment.
- `docs/HYBRID_NPU_PIPELINE.md` — hybrid architecture guide.

---

## 6. Windows Support (via Lemonade OGA / Ryzen AI)

The hybrid burst pipeline is cross-platform. On Windows 11 (native):
- **NPU Backend:** Served by **Lemonade's `oga` backend** (ONNX Runtime GenAI with AMD Ryzen AI / Vitis AI Execution Provider) instead of Linux FastFlowLM.
- **iGPU Target:** Runs via the Vulkan backend (`llama-server.exe -dev Vulkan0`), which works natively on Radeon 8060S under Windows.

### Windows 11 Setup Steps (PowerShell)

```powershell
# 1. Install Lemonade SDK
pip install lemonade-sdk

# 2. Install and verify ONNX Runtime GenAI NPU backend
lemonade backends install oga
lemonade backends --all

# 3. Pull and load lightweight NPU drafter
lemonade pull Qwen2.5-0.5B-Instruct-oga
lemonade load Qwen2.5-0.5B-Instruct-oga

# 4. Run the hybrid pipeline pointing to the Windows Lemonade endpoint
python scripts\run_pipeline.py --device Vulkan0 `
    --npu-url http://127.0.0.1:8000 --npu-model Qwen2.5-0.5B-Instruct-oga
```

> **Note on WSL2:** The AMD XDNA NPU driver does **not** currently support virtualization passthrough to WSL2 containers/VMs. For NPU acceleration, run the pipeline natively on Windows or natively on Linux.
