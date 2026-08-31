# AGENTS.md — q38rocm

## What this repo is
Dedicated single-model deployment package for **Qwen 3.8 27B ROCmFP4_FAST**
on AMD Strix Halo: github.com/julianmb/q38rocm. Public product repo —
halofpx is the multi-model generalization of this one.

## Verify before pushing
```bash
bash -n setup_env.sh run_server.sh quickstart.sh build_engine.sh
bash tests/test_run_server_args.sh
bash tests/test_cache_profile.sh
bash tests/test_build_engine_flags.sh
```

## Layout & facts
- `build_engine.sh` — builds/downloads the ROCmFPX engine.
  Flags: `--prebuilt` `--static` (default) `--shared` `--clean`
  `--rocm-only` `--webui`. Pinned upstream commit via `PINNED_COMMIT`.
- `run_server.sh` — production launcher with profiles:
  `speed | agent | cache | safe` (see README table).
- `quickstart.sh` — 1-command interactive launcher.
- `setup_env.sh` — ROCm/Vulkan env + runtime preflight (fails fast with
  install instructions if libhipblas.so.3 closure is missing).
- `xdna-driver/` — git submodule (amd/xdna-driver) for optional NPU/XRT.

## Gotchas
1. **Engine flags:** fork accepts SINGLE-dash only for `-ctxcp -cpent -cram`;
   double-dash is rejected at startup.
2. **Engine wiring (self-contained, no halofpx):** `engine/bin` symlinks to the
   canonical ROCmFPX build (`~/source/ROCmFPX/build-strix-rocmfp4/bin`) — never
   through the halofpx/hub folder. `build_engine.sh --prebuilt` downloads from
   q38rocm's own releases and replaces a symlinked engine/bin with a real copy
   (guards in build_engine.sh). Weights resolve locally first
   `download_model.sh` downloads into `models/` — the canonical local store;
   repo-root ggufs (legacy) and the `HUB_DIR` fallback in quickstart.sh/
   run_server.sh are checked after it, skipped when absent.
3. **ROCm requirement:** engine needs ROCm 10.0 runtime libs (supports 7.2.x libs for backward compat); never bundle
   them in the repo (decision from issue #5 — documented, not vendored).
4. **MTP:** Qwen 3.8 27B is the model where MTP IS a big win (2.4–2.94x).
   Keep strict-greedy (`--spec-mtp-strict-qwen`) available for agents.
   Speed profile (v1.5.2+) combines MTP + prompt caching + TurboQuant KV —
   measured 7.6x faster warm turns, do NOT revert speed to `--no-cache-prompt`
   based on the old turbo4/checkpoint incompatibility belief (disproven 2026-08-30).
5. Speech pipeline: NPU Whisper + pyannote work formerly staged in the
   `q38rocmDf2` sibling clone now lives in `npuhalo-speech`
   (github.com/julianmb/npuhalo-speech). The duplicate clone has been retired.
6. Commit style: conventional commits; push straight to `main`.

## Benchmarks
Published numbers must be measured (see README benchmark tables and
community-validation notes). Label projections explicitly.
