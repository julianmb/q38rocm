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

* **Upstream Engine Repository:** [`ROCmFPX/ROCmFPX`](https://github.com/ROCmFPX/ROCmFPX) — **official org, now production pin** (migrated 2026-09-02 via #11)
* **Pinned Commit:** `75e67a92b2d230849aec2d6c1f7b1d1fd624e0e0` (`llama.cpp` build `11474`, `v0.3.0-dev`, `v1.7.0`) — includes native DFlash2, strict-qwen MTP, and empty-`data_spec` checkpoint tolerance (previously local patches)
* **Previous Pin:** `charlie12345/ROCmFPX` @ `998d0ca` (v1.6.0) retired — its two cherry-picks are now upstream
* **Pre-built Tarball:** `https://github.com/julianmb/q38rocm/releases/download/v1.7.0/strix-halo-rocmfpx-engine-v1.7.0-linux-x86_64.tar.gz`
* **Verification:** `build_engine.sh --prebuilt` verifies SHA256 checksum `TBD` (populated by `make-release.sh`).
* **Drift resolved (v1.5.3):** the tarball is now built from the pinned commit — `llama-server --version` reports `version: 244 (0fc9568)`, matching source builds. The earlier v1.5.2 tarball (from `12f8b7e`, build 215, a non-ancestor lineage) is superseded; keep reporting `llama-server --version` / `engine/BUILD_INFO.txt` in bug reports anyway.
* **Engine provenance:** both install paths write `engine/BUILD_INFO.txt` (origin, engine build, pinned commit or release URL, tarball/binary digest, applied patches), and `--prebuilt` warns when the binary does not report `PREBUILT_ENGINE_BUILD`. **Include that file in bug reports** — issues #20 and #21 both stalled because a binary could not be mapped back to a source revision.
* **Release-asset guards:** `tests/test_build_engine_flags.sh` asserts that `RELEASE_TARBALL_URL`, the tag inside it, `EXPECTED_TARBALL_SHA` and the `Dockerfile` URL stay in sync; `.github/workflows/verify-release-asset.yml` downloads the published asset and compares its real digest plus archive layout (`/bin/llama-server`). The previous pinned digest (`7352ab06…`) was the **v1.5.0** asset and was never updated, so `--prebuilt` failed its checksum for the whole v1.5.1–v1.5.2 window.

| Compatibility Item | Status | Notes |
|---|---|---|
| **Mesa RADV 26.0** | ✅ Tested | Vulkan Wave64 cooperative-matrix baseline for Strix Halo. |
| **ROCm 7.2.3** | ✅ Compatible | Supported through the engine's backward-compatible ROCm runtime linkage. |
| **ROCm 10.0** | ✅ Recommended | Current runtime baseline; the complete `libhipblas.so.3` dependency closure must be installed. |
| **Kernel IOMMU flags** | ✅ Compatible | Use `iommu=pt` when enabling optional XDNA/NPU support; do not boot with `amd_iommu=off`. |
| **Upstream revision** | ✅ `75e67a9` (v1.7.0) | Pinned to org repo `main`; DFlash2 + strict-qwen native, local patches retired. |


---

## 5. Successor Repository Migration — Completed (2026-09-02)

Charlie moved ROCmFPX development to the [`ROCmFPX/ROCmFPX`](https://github.com/ROCmFPX/ROCmFPX) organization repo — **migrated 2026-09-02 via PR #11 (`75e67a92`)** ("the official ROCmFPX stack and studio"). It is a full TheRock-transitioned upstream sync (11k+ commits vs our pin) with active daily development. `charlie12345/ROCmFPX` remains un-archived but the org repo is where new work lands (type-107 ROCmFP2 collision fix, ROCm 10 multi-GPU docs, MMQ dispatch fix — all Sep 1).

### What the org repo gives us natively

| Capability | Status in org repo | Notes |
|---|---|---|
| **DFlash2 (`draft-dflash`)** | ✅ Native | 22 refs in `common/speculative.cpp` — would retire the Laurent fork dependency for `--profile structured` |
| **`data_spec` checkpoint field** | ✅ Present | `common/common.h` line ~1178 |
| **ROCm 10.0 + Mesa compat** | ✅ Documented | Matches our §4 matrix |
| **ROCmFP2 type-107 fix** | ✅ Sep 1 | Disambiguation + `retag-legacy-rocmfp2.py` audit tool |

### Migration blockers (verified 2026-09-01 against `main` @ `8124bdea`)

| # | Blocker | Impact on q38rocm | Upstream action |
|---|---|---|---|
| 1 | **`--spec-mtp-strict-qwen` missing** (0 refs) | `agent` profile loses boundary-safe greedy MTP | Requested upstream |
| 2 | **Checkpoint restore lacks empty-`data_spec` tolerance** — restores `it->data_spec` unconditionally; prefill-time checkpoints (empty spec) hit the reset path, and there is no `spec-boundary-mismatch` cold fallback either | Our 21×/44×/79× cache+MTP results would regress to full cache wipes on long docs | Requested upstream (with our patch as reference) |
| 3 | **Different lineage** (11k+ commits) | Our two patches (`mtp-prompt-cache-fix`, `router-loading-child-stop-timeout`) must be re-ported, not applied | Port after blockers 1–2 |

### Migration checklist (execute in order, each step gated)

1. ✅ Upstream: `spec-mtp-strict-qwen` support merged in `ROCmFPX/ROCmFPX`
2. ✅ Upstream: empty-`data_spec` checkpoint restore tolerance merged (or our patch ported + accepted)
3. ✅ Local: re-port `patches/*.patch` onto the org-repo base; regenerate `patches/mtp-prompt-cache-fix.patch` from the new tree
4. ✅ Local: `PINNED_COMMIT` bump + `./build_engine.sh --clean` against the org repo (`REPO_URL` change in `build_engine.sh`)
5. ✅ Validate: full `tests/` suite + live cache+MTP A/B at 32K/65K/130K vs the `998d0ca` baseline (23×/44×/79×) — **no regression accepted**
6. ✅ Ship: `./scripts/make-release.sh v1.7.0` + Dockerfile sync (automated)
7. ✅ Add `--profile structured` without the Laurent-fork requirement (DFlash2 is native)
8. ✅ Update §4 baseline + retire this section

### Result

`75e67a9` is now the production pin. Both blockers landed upstream as `0ef57fb8` + `8aee61ec` (credited to @julianmb), verified byte-identical strict-MTP and checkpoint-restore. Local `patches/` retired — build is clean from the org repo.

> **2026-09-02 update:** upstream PR #12 (strict-qwen for `qwen4exp`) was closed as superseded — the same change landed via PR #16 as `9201af4d` (authored by @julianmb, adapted onto vanilla). `main` @ `22496778e` carries it. No action needed on our side; q38rocm's 27B (qwen35 family) was already covered by #11.
