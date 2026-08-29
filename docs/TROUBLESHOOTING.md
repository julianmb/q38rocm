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

### 6. Agent output repeats or turns into random characters
* **Likely Causes:** Non-strict MTP rollback at tool-call boundaries, an aggressive presence penalty, or client-side retries that append duplicate assistant messages.
* **Solution:**
  1. Use the boundary-safe agent profile: `./run_server.sh --profile agent`.
  2. If corruption persists, isolate speculation and checkpoints with `./run_server.sh --profile safe`.
  3. Keep `--presence-penalty 0.0`; values such as `1.5` can push long output toward rare-token gibberish.
  4. Start the client in the intended project/workspace directory. Pi exposes its launch directory to the model; it cannot infer a benchmark stored elsewhere.
  5. Check the client and server logs for repeated tool calls, retries, context-checkpoint churn, or a GPU reset before attributing repeated UI text to MTP.

---

### 7. `glslc not found` during `build_rocmfpx.sh`
* **Root Cause:** Vulkan shader compiler packages are not installed on Ubuntu / Linux host.
* **Solution:**
  Install Vulkan development tools:
  ```bash
  sudo apt-get update && sudo apt-get install -y vulkan-tools libvulkan-dev shaderc
  ```

---

### 8. `failed to find ggml_backend_init` after a manual build
* **Root Cause:** A dynamically linked executable is loading incompatible or incomplete `libggml-*.so` backend modules after the binaries are copied out of the CMake build tree.
* **Solution:** Configure a native static build, which is now the default in `build_engine.sh`:
  ```bash
  cmake -S . -B build-strix \
    -DGGML_BACKEND_DL=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_NATIVE=ON \
    -DGGML_HIP=ON \
    -DGGML_VULKAN=ON \
    -DCMAKE_HIP_ARCHITECTURES=gfx1151
  cmake --build build-strix -j "$(nproc)" --target llama-server
  ```
  `GGML_NATIVE=ON` produces CPU-specific binaries, so build on the target Strix Halo host. Fedora users should also ensure the Vulkan loader/development packages and `glslc` are installed before configuring.

---

### 9. `failed to load prompt from cache` or `prompt cache skip: reason=spec-boundary-mismatch`
* **Root Cause:** When running with MTP speculation (`--mtp` or `MTP=1`) alongside prompt caching, the speculative draft state requires exact boundary matching with the target KV state. If a subsequent request diverges significantly from the cached prompt (e.g., LCP is only a fraction of the cached tokens), the engine cannot safely salvage the trailing draft state without desynchronizing MTP. The engine outputs a warning (`W slot prompt_load: failed to load prompt from cache`) and gracefully falls back to a clean cold prefill (`prompt cache cold fallback: reason=target-draft-restore-rejected`).
* **Solution:**
  1. This is normal and expected fallback behavior when prompts branch significantly under speculative decoding. The server does not crash or error out; it safely invalidates the divergent slot/checkpoints and pre-fills the new prompt cleanly.
  2. For workloads with frequent divergent multi-turn branching, document switches, or deep prompt caching where maximum cache reuse is priority, run the standard cache profile without MTP: `./run_server.sh --profile cache` (which defaults to `MTP=0`).

---

### 10. `File Not Found` on `/v1/embeddings` in router mode (`--models-preset`)
* **Symptom:** the router loads the embedding child (log shows `n_embd`), but a request returns `{"error":{"message":"File Not Found",...,"code":404}}`.
* **Root Cause:** `/v1/embeddings` is registered as a **POST-only** route. Anything that issues a `GET` against it — a health probe, a browser address bar, a client that follows a redirect and downgrades `POST` → `GET` — gets a 404 from the HTTP layer. The route itself is proxied correctly for POST (verified on the v1.5.0 and v1.5.2 prebuilts and on a current source build).
* **Solution:**
  1. Send a POST (this is what the OpenAI clients do):
     ```bash
     curl -X POST http://127.0.0.1:8080/v1/embeddings \
       -H 'Content-Type: application/json' \
       -d '{"model":"bge","input":"hi"}'
     ```
  2. Confirm which engine you are actually on — a server-side 404 that persists for POST means the binary is not the build you think it is:
     ```bash
     ./engine/bin/llama-server --version   # e.g. "version: 215 (12f8b7e)"
     ```
  3. If `--prebuilt` aborts with a checksum mismatch, the pinned digest in `build_engine.sh` is stale; see `docs/UPSTREAM_TRACKING.md`.
* **Not a bug:** unknown or wrong-method paths return `4xx` **without** stopping the router (verified against `/v1/nonexistent`, `/nope`, `GET /v1/embeddings`), and killing a child instance does not bring the router down — the next request to that model returns `500 proxy error: Could not establish connection` and the router keeps serving.

---

## ❓ Frequently Asked Questions (FAQ)

### Q: Can I run 262K context window models on a 32 GB system?
**A:** Yes, for **hybrid attention models** (e.g. Qwen3.6/3.8-27B with 16 full-attention layers). Because linear attention layers use a fixed recurrent state rather than per-token KV cache, 262K context requires only ~6 GB of KV cache in `q8_0`/`turbo4`. Combined with the `STRIX_LEAN` weight quant (~14.6 GB), total peak RAM stays under ~24 GB.

### Q: Why does `llama-bench` not report speedups for MTP?
**A:** Standard `llama-bench` does not accept speculative decoding flags (`--spec-type`). To benchmark MTP speedup, launch `llama-server` in completion mode or use interactive `llama-cli` timing outputs.

---

## 💡 Support & Issues

For bugs in ROCmFPX kernels, submit issues or pull requests to upstream [charlie12345/ROCmFPX](https://github.com/charlie12345/ROCmFPX).

