# Upstream Tracking & Workaround Matrix

This document tracks upstream `llama.cpp` and `ROCmFPX` patches, speculative decoding state interactions, known boundary limitations, and production workarounds for AMD Strix Halo deployments.

---

## 1. Speculative Decoding & Prompt Cache Interplay (Issue #19)

### Technical Mechanics
In `llama-server`, standard autoregressive inference (`MTP=0`) supports prefix tree KV reuse: when a prompt shares a Longest Common Prefix (`LCP`) with a cached slot, the server keeps the prefix tokens in the KV cache and truncates only the divergent suffix.

However, when **Multi-Token Prediction (MTP)** or other speculative decoding methods are enabled:
1. The engine maintains coupled state: target model KV context + draft recurrent state (`rs_seq`).
2. When a subsequent request diverges by more tokens than the draft recurrent rollback depth (`delta > llama_n_rs_seq(ctx)`), the draft state cannot be rolled back without desynchronizing draft generation.
3. The server safely skips checkpoint restoration (`reason=spec-boundary-mismatch`), logs `W slot prompt_load: failed to load prompt from cache`, clears the divergent slot/draft state, and initiates a clean **cold prefill fallback**.

```
[Request 1: 93,260 tokens] ──> Saved to slot & checkpoints (MTP draft boundary active)
                                       │
[Request 2: 186,726 tokens] ───────────┴──> Common prefix = 18,967 tokens
                                            Divergence = 74,293 tokens (> n_rs_seq)
                                            ├── Draft state cannot safely rewind 74k tokens
                                            ├── Engine emits: reason=spec-boundary-mismatch
                                            └── Safe fallback: clears slot & cold-prefills Request 2
```

---

## 2. Workaround Matrix

Depending on your workload characteristics, use the appropriate profile or launcher configuration:

| Workload Type | Recommended Profile / Flags | Speculation | KV Cache / Prefix Behavior |
|---|---|---|---|
| **Single-turn or Monotonic Chat** | `./run_server.sh --profile speed` *(Default)* | MTP ($K=4$) enabled | Peak decode speed (34–36 tok/s). Monotonic history reuses cache smoothly. |
| **Branching Agent / Document QA** | `./run_server.sh --profile cache` | MTP disabled ($K=0$) | Maximum prefix tree reuse and RAM checkpoints (16–64) across arbitrary prompt branches. |
| **Concurrent Independent Sessions** | `./run_server.sh --profile cache --slots 4` | MTP disabled ($K=0$) | Isolates sessions across slots so branching in Session A does not evict Session B. |
| **Structured Output Burst** | LaurentZuijdwijk fork + DFlash2 (`--spec-draft-n-max 15`) | DFlash2 Block 16 | Up to 80 tok/s on structured JSON/code; requires sidecar GGUF. |

---

## 3. Upstream Patch & PR Registry

| Component / Patch | Repository / PR | Status | Scope |
|---|---|---|---|
| `router-loading-child-stop-timeout.patch` | Local / `patches/` | ✅ Applied by `build_engine.sh` (not in `v1.5.2` prebuilt) | Terminates a router child that is still loading instead of waiting out `stop-timeout` (issue #21). |
| `mtp-prompt-cache-fix.patch` | Local / `patches/` | ✅ Applied in `v1.5.0+` | Allows MTP checkpoint rollback during prefill when replaying matching prefix batches. |
| **DFlash2 Block Diffusion** | `ggml-org/llama.cpp#27342` | ⏳ Upstream Under Review | Adds `draft-dflash` block-diffusion speculative decoding support. |
| **Vulkan Batched Mat-Vec** | `LaurentZuijdwijk/llama.cpp` (`b10681`) | 🔬 Community Fork | Fixes Vulkan batched mat-vec for FP4 + speculative decoding sidecars. |
| **Selective Draft State Rollback** | Upstream RFC | 📋 Tracking | Proposed RFC to decouple draft recurrent state reset from primary KV prefix truncation on large divergences. |

---

## 4. Engine Pinned Baseline

* **Upstream Engine Repository:** [`charlie12345/ROCmFPX`](https://github.com/charlie12345/ROCmFPX)
* **Pinned Commit:** `0fc9568e07ccc8553010864cb8db1957e629cbfa` (`llama.cpp` build `244`) — **intentionally held here** (2026-08-29). Upstream `origin/main` (`c49ebdb`) is 13 commits ahead but consists solely of the experimental ROCmI4/IU4 `W4A4` path (`experimental/rocmi4-iu4`, `rocmi4-exact`, `gfx1151-mmq-tuning`). No prompt-cache/MTP or stability fixes are in that window; bumping would pull an unvalidated quantization experiment into the stable Strix Halo release.
* **Pre-built Tarball:** `https://github.com/julianmb/q38rocm/releases/download/v1.5.2/strix-halo-rocmfpx-engine-v1.5.2-linux-x86_64.tar.gz`
* **Verification:** `build_engine.sh --prebuilt` verifies SHA256 checksum `70d11cec4fd6c148a050f80a0422d563a928c39f849e600d6b59b1d620820aa7`.
* **⚠️ Prebuilt / pinned-source drift (issue #20):** the `v1.5.2` tarball was built from `12f8b7e` (build `215`), which is **not** an ancestor of the pinned `0fc9568e` (build `244`) and is older than the `v1.5.0` engine (`version: 244 (0fc9568)`). A source build at the pinned commit therefore produces a *newer* engine than the current prebuilt. Until a release is rebuilt from the pinned commit, always report `llama-server --version` when filing engine bugs.
* **Engine provenance:** both install paths write `engine/BUILD_INFO.txt` (origin, engine build, pinned commit or release URL, tarball/binary digest, applied patches), and `--prebuilt` warns when the binary does not report `PREBUILT_ENGINE_BUILD`. **Include that file in bug reports** — issues #20 and #21 both stalled because a binary could not be mapped back to a source revision.
* **Release-asset guards:** `tests/test_build_engine_flags.sh` asserts that `RELEASE_TARBALL_URL`, the tag inside it, `EXPECTED_TARBALL_SHA` and the `Dockerfile` URL stay in sync; `.github/workflows/verify-release-asset.yml` downloads the published asset and compares its real digest plus archive layout (`/bin/llama-server`). The previous pinned digest (`7352ab06…`) was the **v1.5.0** asset and was never updated, so `--prebuilt` failed its checksum for the whole v1.5.1–v1.5.2 window.
