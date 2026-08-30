# 🔬 Quantization Guide: FP8 / BF16 to ROCmFPX on AMD Strix Halo

This document provides a technical deep-dive into converting full-precision (BF16) or FP8 models into **ROCmFP4** and **ROCmFPX** quantized GGUF models tailored for **AMD Strix Halo (`gfx1151`)**.

---

## 💡 What are ROCmFP4 and ROCmFPX?

Standard `llama.cpp` quantization types (`Q4_K_M`, `Q5_K_S`, etc.) format weights into generic integer block representations (`q4_K`, `q8_0`). While versatile across CPUs and NVIDIA GPUs, these formats do not map efficiently to AMD's RDNA 3.5 / CDNA matrix core instructions on Strix Halo (`gfx1151`).

**ROCmFP4 / ROCmFPX** quantization introduces AMD-native FP4 / FPX tensor encodings:
1. **Packed FP4/FPX Matrix Layouts:** Weights are packed into bit layouts designed for direct ingestion by `gfx1151` matrix multiplication instructions, reducing instruction overhead during prefill and decode.
2. **Selective Tensor Protection (Routing Presets):** Rather than uniformly quantizing every tensor, ROCmFPX allows routing specific critical layers (token embeddings, attention projections, MoE router gates) to higher bitrates while aggressively quantizing the bulk feed-forward / expert matrices.

---

## 🎯 Quantization Routing Presets

When quantizing a model for Strix Halo, two primary presets are recommended depending on the target workload:

### 1. `Q4_0_ROCMFP4_COHERENT` (Speed Preset)
- **Target Size:** ~18.3 GiB for a 35B parameter MoE model (~4.0 bits per weight equivalent).
- **Tensor Strategy:**
  - **Expert / FFN Matrices:** Quantized to 4-bit `ROCmFP4`.
  - **Attention (Q, K, V, O) & Embeddings:** Maintained at higher precision (`Q8_0` or `FP16`).
  - **MoE Gate/Router:** Preserved at high precision to maintain correct expert selection.
- **Decoding Speed:** Maximum throughput (~67.4 t/s on 35B MoE).
- **Best For:** High-speed chat, long-context prompt processing, general reasoning.

### 2. `Q6_0_ROCMFPX_AGENT` (Quality Preset)
- **Target Size:** ~30.0 GiB for a 35B parameter MoE model (~6.0 bits per weight equivalent).
- **Tensor Strategy:**
  - **Expert / FFN Matrices:** Quantized to 6-bit `ROCmFPX`.
  - **Embeddings, Attention & Output Head:** Kept near full precision.
  - **Protected Structures:** JSON syntax, tool-calling XML tags, code indentation, and structured output patterns.
- **Decoding Speed:** High fidelity (~49.3 t/s on 35B MoE).
- **Best For:** Strict agentic workflows, complex coding tasks, tool calling, JSON schema enforcement.

---

## 🔄 Step-by-Step Conversion Pipeline

### Step 1: Obtain the Source Checkpoint
You can start from either a Hugging Face **BF16** repository or an **FP8** repository:
```bash
# Example: Download BF16 or FP8 base model
hf download Qwen/Qwen3.8-27B --local-dir ./Qwen3.8-27B-bf16   # or your FP8 checkpoint
```

### Step 2: Convert to Intermediate GGUF (F16 or FP8)
Use `convert_hf_to_gguf.py` from the ROCmFPX fork:
```bash
python3 engine/src/convert_hf_to_gguf.py ./Qwen3.8-27B-bf16 \
    --outfile ./Qwen3.8-27B-F16.gguf \
    --outtype f16
```

> ⚠️ **Memory Tip during Intermediate Conversion:** Converting a 27B BF16 model requires ~55GB of system RAM. If converting on a 32GB or 64GB machine, ensure swap is enabled or convert on a larger build host first.

### Step 3: Quantize to ROCmFPX GGUF
Run `llama-quantize` with the custom ROCmFPX preset flags:

#### For Speed (`Q4_0_ROCMFP4_COHERENT`):
```bash
./engine/bin/llama-quantize \
    ./Qwen3.8-27B-F16.gguf \
    ./Qwen3.8-27B-ROCmFP4-FAST.gguf \
    Q4_0_ROCMFP4_FAST
```

#### For Quality (`Q6_0_ROCMFPX_AGENT`):
```bash
./engine/bin/llama-quantize \
    ./Qwen3.8-27B-F16.gguf \
    ./Qwen3.8-27B-ROCmFP8.gguf \
    Q8_0_ROCMFPX
```

---

## 📌 Important Conversion Caveats & Best Practices

1. **Importance Matrix (`imatrix`):**
   - While `imatrix` calibration can improve perplexity in standard GGUF quants, generating an `imatrix` file for 35B+ models requires loading the full F16 model into VRAM/RAM simultaneously.
   - On memory-constrained Strix Halo setups, **explicit fallback agent routing presets** (`Q4_0_ROCMFP4_COHERENT` and `Q6_0_ROCMFPX_AGENT`) provide comparable accuracy without requiring an `imatrix` pre-pass.

2. **Single-File Output:**
   - Single GGUF files (e.g. 18.3 GiB and 30.0 GiB) are significantly easier to deploy and manage than sharded GGUF splits (`-00001-of-00002.gguf`).
   - Use Git LFS (`.gitattributes`) when pushing single-file GGUFs to Hugging Face.

3. **Verify SHA256 Checksums:**
   - Always verify weights after quantization to prevent silent corruption:
   ```bash
   sha256sum ./Qwen3.8-27B-ROCmFP4-FAST.gguf > SHA256SUMS
   ```
