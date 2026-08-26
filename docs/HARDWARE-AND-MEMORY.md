# ⚙️ Hardware, BIOS & Memory Management Guide for AMD Strix Halo

This document details the **Unified Memory Architecture (UMA)** on AMD Strix Halo (`gfx1151`), BIOS/AGESA memory configuration, peak RAM measurement, and system memory compatibility matrices.

---

## 🏛️ Strix Halo Architecture Overview

AMD Strix Halo (e.g. **Ryzen AI Max+ 395**) utilizes a **Unified Memory Architecture (UMA)** with a 256-bit LPDDR5X memory bus providing ~270 GB/s memory bandwidth. 

Unlike discrete GPUs with dedicated VRAM, Strix Halo shares a single physical pool of high-speed LPDDR5X RAM between the CPU cores and the integrated RDNA 3.5 APU graphics engine (`gfx1151`).

```
+-------------------------------------------------------------------+
|                   Physical LPDDR5X Unified RAM                    |
|                         (32GB / 64GB / 128GB)                     |
+---------------------------------+---------------------------------+
|   System OS & Host Memory       | APU Graphics Pool (UMA / VRAM)  |
|  (Linux Kernel, Buffers, Apps)  | (GGUF Model Weights & KV Cache) |
+---------------------------------+---------------------------------+
```

---

## ⚠️ Essential BIOS / AGESA Configuration

By default, factory BIOS settings on many Strix Halo laptops and mini-PCs (e.g., Beelink GTR9 Pro, Asus ROG Flow) cap the GPU's VRAM allocation to **16 GB or 32 GB**.

To run long-context inference (32K to 262K context windows):

1. **Enter BIOS / AGESA Setup:** Reboot your device and enter BIOS setup (usually `F2` or `DEL`).
2. **Locate UMA Frame Buffer Size:** Navigate to `Advanced -> AMD CBS -> NBIO Common Options -> GFX Configuration`.
3. **Adjust Memory Allocation:**
   - Set **UMA Mode** to `UMA_SPECIFIED` or `Auto`.
   - Set **UMA Frame Buffer Size** to maximum available (e.g. **64G**, **96G**, or **128G** depending on physical RAM).
4. **Save & Reboot.**

Verify OS-visible memory in Linux:
```bash
free -h
# Should show max available memory exposed to Linux host
```

---

## 📊 Measured Peak Memory Footprints (35B MoE / `q8_0` KV Cache)

Below are real-world measured memory usage data points for the **Speed (`18.35 GiB`)** and **Quality (`30.04 GiB`)** candidates across different context lengths:

| Context Window | Speed Candidate (18.3 GiB) | Quality Candidate (30.0 GiB) | Notes & RAM Recommendation |
|---:|:---:|:---:|---|
| **512 tokens** | ~20 GiB | ~32 GiB | Trivial. Fits on 32GB systems. |
| **4,096 tokens** | ~21 GiB | ~33 GiB | Fits comfortably on 32GB (Speed) or 64GB (Quality). |
| **32,768 tokens** | **~36.6 GiB** *(measured)* | **~59.8 GiB** *(measured)* | **Rigorously measured via `/usr/bin/time -v`**. |
| **131,072 tokens** | ~50 GiB *(est.)* | ~82 GiB *(est.)* | Requires 64GB (Speed) or 96GB (Quality). |
| **262,144 tokens** *(Max)* | **~85 GiB** *(est. sustained)* | **~106 GiB** *(est.)* | **Requires 128GB physical RAM.** |

> 💡 **Understanding Prompt-Fill vs. Sustained Generation Memory:**
> - During **prompt processing (`pp262144`)**, peak RSS reached **~30.48 GiB** on the Speed Candidate because the KV cache is built iteratively.
> - During **sustained generation (`tg`)** with 262K context resident in memory, the full 8-bit KV cache requires ~50+ GB on top of the model weights (~18.3 GiB) and OS overhead (~5 GiB), total ~85 GiB.

---

## 💻 System RAM Compatibility Matrix

- **32 GB Systems:**
  - **Speed Candidate:** Supported up to ~8K–16K context window.
  - **Quality Candidate:** Supported up to 4K context window.
- **64 GB Systems (The Sweet Spot):**
  - **Speed Candidate:** Fully supports up to 128K context window.
  - **Quality Candidate:** Fully supports up to 32K context window.
- **96 GB Systems:**
  - **Speed Candidate:** Fully supports 128K–262K context window.
  - **Quality Candidate:** Fully supports up to 64K context window.
- **128 GB Systems (No Compromises):**
  - **Speed & Quality Candidates:** Native 262,144 token max context on all models without swapping.

---

## 🔧 Essential Linux Environment Variables

To enable unified memory and ROCm graphics overrides on Strix Halo, always set these variables before launching `llama-cli` or `llama-server`:

```bash
# Override GFX target version for Strix Halo APU (gfx1151)
export HSA_OVERRIDE_GFX_VERSION=11.5.1

# Enable HIP Unified Memory Allocation
export GGML_HIP_ENABLE_UNIFIED_MEMORY=1
```

---

## 🧠 RAM-Aware Prompt Cache Profiles

The launchers automatically select a prompt-cache profile from physical RAM:

| System RAM | RAM Prompt Cache | Context Checkpoints | Checkpoint Interval |
|---:|---:|---:|---:|
| Under 56 GiB | 8 GiB | 16 | 4,096 tokens |
| 56–111 GiB | 16 GiB | 32 | 4,096 tokens |
| 112+ GiB | 32 GiB | 64 | 4,096 tokens |

Cache mode enables prompt caching, context checkpoints, slot-save endpoint storage, continuous batching, unified KV, and `--no-mmap`. It primarily accelerates repeated prefixes, agent loops, and long-document follow-up requests; it does not increase the memory-bandwidth-bound single-token decode ceiling.

When MTP is enabled alongside prompt caching (`--profile cache --mtp`), identical or monotonically extended prefixes reuse cache seamlessly. However, when prompts diverge significantly (e.g., LCP is only a fraction of the cached context), MTP draft boundary constraints prevent salvaging the divergent tail, and the engine gracefully falls back to cold prefill (`spec-boundary-mismatch`). The launchers therefore expose explicit modes:

```bash
# Default: fastest single-stream decode with embedded MTP.
./run_server.sh --profile speed

# Reusable-prefix mode: disables MTP for maximum cache reuse across divergent prompts.
./run_server.sh --profile cache
```

Override any setting when launching:

```bash
CACHE_RAM_MIB=32768 CTX_CHECKPOINTS=16 SLOTS=2 ./run_server.sh --profile cache

# Pin model pages only after configuring an adequate memlock limit.
MLOCK=1 ./run_server.sh
```

`MLOCK=1`, multiple slots, TTM overrides, and bootloader changes are intentionally not enabled automatically because they can exhaust host memory or destabilize the system.
