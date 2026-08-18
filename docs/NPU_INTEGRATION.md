# NPU Integration (Optional) — AMD XDNA 2 on Strix Halo

This document is the complete reference for optionally accelerating **Qwen 3.8 27B** by combining the **AMD XDNA 2 NPU** (`/dev/accel/accel0`) with the **Radeon 8060S iGPU** (`Vulkan0` / `KHR_coopmat`).

> **Important:** NPU acceleration is **fully optional**. The server works perfectly without it. The NPU does **not** improve sustained decode speed — see the definitive findings below.

> ⚠️ **Scope note:** All NPU findings, benchmarks, and the hybrid pipeline below were **only tested on Qwen 3.8 27B** (dense, ROCmFP4_FAST).

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

XRT is built from the AMD XDNA driver source (see `xdna-driver/` in this repo):
```bash
cd /home/user/source/q38rocm/xdna-driver
git submodule update --init --recursive
cd xrt/build
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

---

## 4. Hybrid Pipeline (optional, advanced)

The `npuhalo` research workspace (`/home/user/source/npuhalo/`) contains a hybrid pipeline that bursts the prompt prefix on the NPU, then hands off to the iGPU for verification:

```bash
cd /home/user/source/npuhalo
python3 scripts/run_pipeline.py --device Vulkan0 --draft-n 4 --npu-burst-tokens 24
```

This serves an OpenAI-compatible API on port **11435** with the 1.8× first-token speedup.

---

## 5. Related research workspace

The full empirical study lives in `/home/user/source/npuhalo/`:
- `docs/REPORT.md` — full technical report (tools, code, paths, findings).
- `docs/final_verdict.md` — reconciled verdict and forward-path assessment.
- `docs/HYBRID_NPU_PIPELINE.md` — hybrid architecture guide.
