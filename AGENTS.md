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
2. **Hub path:** `quickstart.sh` resolves weights/engine via
   `HUB_DIR="${HALOFPX_HUB_DIR:-${HOME}/source/halofpx-research}"` —
   intentional default, do not hardcode other absolute paths.
3. **ROCm requirement:** engine needs ROCm 7.2.x runtime libs; never bundle
   them in the repo (decision from issue #5 — documented, not vendored).
4. **MTP:** Qwen 3.8 27B is the model where MTP IS a big win (2.4–2.94x).
   Keep strict-greedy (`--spec-mtp-strict-qwen`) available for agents.
5. Speech pipeline: NPU Whisper + pyannote work formerly staged in the
   `q38rocmDf2` sibling clone now lives in `npuhalo-speech`
   (github.com/julianmb/npuhalo-speech). The duplicate clone has been retired.
6. Commit style: conventional commits; push straight to `main`.

## Benchmarks
Published numbers must be measured (see README benchmark tables and
community-validation notes). Label projections explicitly.
