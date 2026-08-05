# 📊 Benchmarking & Performance Profiling Guide for Strix Halo (gfx1151)

This guide explains how to accurately benchmark throughput, profile memory consumption, and measure context performance for ROCmFPX models on AMD Strix Halo.

---

## 🛠️ Benchmark Tools Overview

We use two primary tools for profiling:
1. **`llama-bench`**: Measuers prompt-processing (`pp`) and token-generation (`tg`) throughput in tokens per second (t/s).
2. **`/usr/bin/time -v`**: Profiles exact OS peak Resident Set Size (RSS) and wall-clock load time.

---

## 🚀 Running Throughput Benchmarks (`llama-bench`)

### Basic 512-Token Prompt & 128-Token Generation Test:
```bash
ROCmFPX/build-strix-rocmfp4/bin/llama-bench \
    -m ./Ornith-1.0-35B-ROCmFPX-Speed-StrixHalo.gguf \
    -dev ROCm0 -ngl 999 -fa on \
    -p 512 -n 128 \
    -ctk q8_0 -ctv q8_0 \
    -r 3
```

### Context Scaling Benchmark Suite (4K to 262K):
To benchmark prompt-fill speed across context sizes:
```bash
# Test prompt fill at 512, 4096, 32768, 131072, and 262144 tokens
ROCmFPX/build-strix-rocmfp4/bin/llama-bench \
    -m ./Ornith-1.0-35B-ROCmFPX-Speed-StrixHalo.gguf \
    -dev ROCm0 -ngl 999 -fa on \
    -p 512,4096,32768,131072,262144 -n 0 \
    -ctk q8_0 -ctv q8_0 \
    -r 1
```

---

## 📈 Real-World Benchmark Results Summary

Measured on **Ubuntu 24.04, ROCm 7.2.3, FlashAttention Enabled**:

| Benchmark Parameter | Speed (`Q4_0_ROCMFP4_COHERENT`) | Quality (`Q6_0_ROCMFPX_AGENT`) |
|---|---:|---:|
| **Prompt Processing (`pp512`)** | **1,202.75 ± 2.10 t/s** | **760.36 ± 2.10 t/s** |
| **Token Generation (`tg128`)** | **67.43 ± 0.07 t/s** | **49.35 ± 0.05 t/s** |
| **Context Fill (`pp4096`)** | **1,153.38 ± 0.53 t/s** | **737.51 ± 0.00 t/s** |
| **Long Context Fill (`pp32768`)** | **845.44 ± 1.31 t/s** | **600.43 ± 0.00 t/s** |
| **Extended Context (`pp131072`)** | **447.89 ± 0.00 t/s** | *Not tested* |
| **Max Context (`pp262144`)** | **217.96 ± 0.00 t/s** | *Not tested* |

---

## 🔍 Profiling Real Peak RSS Memory (`/usr/bin/time -v`)

To accurately measure peak unified memory usage including KV cache allocation:

```bash
/usr/bin/time -v ROCmFPX/build-strix-rocmfp4/bin/llama-cli \
    -m ./Ornith-1.0-35B-ROCmFPX-Speed-StrixHalo.gguf \
    -dev ROCm0 -ngl 999 -fa on \
    -c 32768 -ctk q8_0 -ctv q8_0 \
    -p "Test prompt for memory profiling" -n 128
```

Look for `Maximum resident set size (kbytes)` in the stderr output:
- **32,768 Context on Speed (Q4):** `38,332,948 kB` (~36.55 GiB)
- **32,768 Context on Quality (Q6):** `62,743,396 kB` (~59.83 GiB)

---

## ⚠️ Notes on MTP (Multi-Token Prediction / Speculative Decoding)

1. The ROCmFPX build script includes MTP speculative decoding support (`scripts/build-strix-rocmfp4-mtp.sh`).
2. However, standard `llama-bench` does not currently accept the `--spec-type` flag required for speculative decoding benchmarks.
3. To benchmark MTP, use `llama-server` in completion mode with request-level speculative decoding parameters (`n_max=2`, `p_min=0.75`).
