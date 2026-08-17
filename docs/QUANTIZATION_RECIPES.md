# ROCmFPX Quantization Recipes for AMD Strix Halo (gfx1151)

This document details the quantization algorithms, layout formats, and conversion pipelines used to create high-throughput **ROCmFP4** and 3-bit GGUF models for AMD Strix Halo.

---

## 1. Quantization Formats Overview

| Quantization Preset | BPW | Block Size | Target Subsystem | Characteristics & Use Cases |
|---|---|---|---|---|
| **`Q8_0_ROCMFPX` (`ROCmFP8`)** | **8.25** | **32** | **Vulkan0 / ROCm0** | **Lossless 8-bit precision (<0.003 PPL delta, 26.25 GiB)** |
| **`Q4_0_ROCMFP4_FAST`** | **4.26** | **32** | **Vulkan0 Wave64 / ROCm0** | **Primary target for maximum MTP speculative throughput (36 tok/s)** |
| **`Q4_0_ROCMFP4_STRIX_LEAN`** | **4.34** | **32** | **Vulkan0 / ROCm0** | Preserves embedding and final norm layers in FP16 |
| **`Q3_K_M`** | **3.95** | **Mixed** | **Vulkan0 / CPU** | Standard k-quant medium (12.56 GiB) |
| **`Q3_K_S`** | **3.59** | **Mixed** | **Vulkan0 / CPU** | Small 3-bit quant (11.40 GiB), fastest unassisted decode (16.69 t/s) |
| **`Q2_0_ROCMFP2`** | **2.69** | **32** | **Vulkan0 / Memory Constrained** | Ultra-compact 2-bit layout (8.56 GiB) |

---

## 2. ROCmFP4 & 8-Bit Matrix Layout & Hardware Alignment

On AMD Strix Halo (Radeon 8060S / RDNA 3.5 / `gfx1151`), the Vulkan RADV driver accelerates matrix multiplication via cooperative matrix instructions (`KHR_coopmat`):
- **Wave64 Dispatch:** 64-thread SIMD execution aligned with RDNA 3.5 dual-issue compute units.
- **Block Size (32):** Every group of 32 weights shares a single scaling factor, matching hardware vector register alignment (32 elements per half-wave).
- **8-Bit Execution Model:** RDNA 3.5 is a consumer client APU architecture that uses INT8 vector dot products and register-level unpacking to FP16 cooperative matrix ALUs. Because LLM generation is strictly **memory-bus bandwidth bound** (rather than compute ALU bound), streaming 8-bit weights (26.25 GB) across the 273 GB/s bus saves 50% memory bandwidth over FP16 (54.6 GB), delivering **18.96 tok/s** with zero precision loss.
- **4-Bit Performance King:** `ROCmFP4` halves the transfer payload again to **13.55 GB**, unlocking **36.04 tok/s** with MTP speculative decoding.
- **MTP Head Preservation:** Speculative prediction heads (`mtp_block.dense`, `mtp_block.norm`) are automatically preserved in high-precision (FP16 or Q8_0) during the quantize pass to maintain 80%+ draft acceptance.

---

## 3. Conversion Pipeline (Step-by-Step)

### Step 1: Convert Hugging Face Safetensors to BF16 GGUF
```bash
python3 /path/to/llama.cpp/convert_hf_to_gguf.py \
  /path/to/Qwen3.8-27B-Instruct \
  --outfile Qwen3.8-27B-BF16.gguf \
  --outtype bf16
```

### Step 2: Quantize to ROCmFP4_FAST
```bash
./scripts/convert_and_quant.sh \
  Qwen3.8-27B-BF16.gguf \
  ./models
```

Or execute `llama-quantize` directly:
```bash
llama-quantize \
  Qwen3.8-27B-BF16.gguf \
  Qwen3.8-27B-ROCmFP4-FAST.gguf \
  Q4_0_ROCMFP4_FAST \
  $(nproc)
```

---

## 4. Asymmetric TurboQuant KV Cache

To prevent KV cache memory from overtaking weight memory during long-context generation (32K to 262K tokens), ROCmFPX implements **Asymmetric TurboQuant**:
- **Key Cache (`-ctk q8_0`):** Retains 8-bit precision to maintain sharp attention routing.
- **Value Cache (`-ctv turbo4`):** Compresses token representations to 4-bit packed integer blocks with near-zero perplexity impact.

---

## 5. Verification & Perplexity Testing

Verify tensor block integrity and perplexity on Strix Halo:
```bash
llama-perplexity \
  -m Qwen3.8-27B-ROCmFP4-FAST.gguf \
  -dev Vulkan0 \
  -ngl 99 \
  -f wikitext-2-raw-v1.test.txt \
  -c 4096
```
