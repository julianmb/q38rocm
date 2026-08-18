# 🛠️ Troubleshooting & FAQ Guide for AMD Strix Halo (gfx1151)

This document addresses common issues, error messages, and optimization solutions when running ROCmFPX on AMD Strix Halo APUs (`gfx1151`).

---

## 🔍 Diagnostics First: Run `strix_diag.sh`

Before troubleshooting individual error messages, run the built-in diagnostic script:

```bash
./scripts/strix_diag.sh --fix-env
```

This checks Linux kernel support, OS-visible RAM, ROCm drivers (`hipcc`, `rocminfo`), Vulkan shader compiler (`glslc`), and required environment variables.

---

## 🚨 Common Error Messages & Solutions

### 1. `HIP error: out of memory` or `Failed to allocate UMA memory`
* **Root Cause:** Operating system-visible memory is lower than expected, or BIOS AGESA UMA VRAM limits are capping memory.
* **Solution:**
  1. Reboot into AGESA/BIOS setup (usually `F2` or `DEL`).
  2. Navigate to `Advanced -> AMD CBS -> NBIO Common Options -> GFX Configuration`.
  3. Set **UMA Mode** to `UMA_SPECIFIED` or `Auto`.
  4. Set **UMA Frame Buffer Size** to the maximum available (e.g. 64G, 96G, or 128G).
  5. Ensure `export GGML_HIP_ENABLE_UNIFIED_MEMORY=1` is exported in your environment.

---

### 2. Low Token Generation Speed (`tg < 20 t/s` on 27B models)
* **Root Cause:** Model is running on `ROCm0` backend instead of `Vulkan0`, or MTP speculative decoding is disabled.
* **Solution:**
  1. Ensure `glslc` (Vulkan shader compiler) is installed (`sudo apt install vulkan-tools shaderc`).
  2. Force Vulkan backend: `DEVICE=Vulkan0 ./scripts/run_inference.sh cli speed /path/to/model.gguf`.
  3. Enable MTP speculative decoding if running a model with an MTP head: `MTP=1 DEVICE=Vulkan0 ./scripts/run_inference.sh cli speed /path/to/model.gguf`.

---

### 3. `HSA_OVERRIDE_GFX_VERSION` missing or unrecognized target
* **Root Cause:** ROCm stack does not natively recognize `gfx1151` without the version override flag.
* **Solution:**
  Export the environment variable in your shell or `.env` file:
  ```bash
  export HSA_OVERRIDE_GFX_VERSION=11.5.1
  ```

---

### 4. MTP Speculative Decoding giving no speedup or throwing `X < Y` position check errors
* **Root Cause:** Using a stale `llama.cpp` build that predates the M-RoPE batch fix for MTP (`src/llama-batch.cpp`).
* **Solution:**
  Rebuild the ROCmFPX toolchain from latest `origin/main`:
  ```bash
  ./scripts/build_rocmfpx.sh
  ```

---

### 5. Intermediate F16 GGUF file taking too much disk space
* **Root Cause:** Converting a 27B–35B model creates an intermediate ~50GB–70GB `model-F16.gguf` file prior to quantization.
* **Solution:**
  Pass the `--clean-f16` flag to automatically delete the intermediate F16 file after quantization succeeds:
  ```bash
  ./scripts/convert_and_quant.sh /path/to/hf_model ./output_dir --clean-f16
  ```

---

### 6. `glslc not found` during `build_rocmfpx.sh`
* **Root Cause:** Vulkan shader compiler packages are not installed on Ubuntu / Linux host.
* **Solution:**
  Install Vulkan development tools:
  ```bash
  sudo apt-get update && sudo apt-get install -y vulkan-tools libvulkan-dev shaderc
  ```

---

## ❓ Frequently Asked Questions (FAQ)

### Q: Can I run 262K context window models on a 32 GB system?
**A:** Yes, for **hybrid attention models** (e.g. Qwen3.6/3.8-27B with 16 full-attention layers). Because linear attention layers use a fixed recurrent state rather than per-token KV cache, 262K context requires only ~6 GB of KV cache in `q8_0`/`turbo4`. Combined with the `STRIX_LEAN` weight quant (~14.6 GB), total peak RAM stays under ~24 GB.

### Q: Why does `llama-bench` not report speedups for MTP?
**A:** Standard `llama-bench` does not accept speculative decoding flags (`--spec-type`). To benchmark MTP speedup, launch `llama-server` in completion mode or use interactive `llama-cli` timing outputs.

---

## 💡 Support & Issues

For bugs in ROCmFPX kernels, submit issues or pull requests to upstream [charlie12345/ROCmFPX](https://github.com/charlie12345/ROCmFPX).
