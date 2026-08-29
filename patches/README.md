# Engine patches

`build_engine.sh` applies every patch in this directory to the pinned ROCmFPX
checkout before building, and refuses to build if one neither applies nor is
already applied. Patches are a carry cost: re-check the drop condition each time
`PINNED_COMMIT` moves.

| Patch | Fixes | Where it ships | Upstream | Drop when |
|---|---|---|---|---|
| `mtp-prompt-cache-fix.patch` | MTP checkpoint restore aborted on checkpoints captured during prefill (`common_speculative_set_state` with no boundary rows) — issue #14 | ✅ in the v1.5.0 prebuilt | ❌ not submitted | Upstream `charlie12345/ROCmFPX` (or `ggml-org/llama.cpp`) handles empty draft state on rollback |
| `router-loading-child-stop-timeout.patch` | Router waited the full `stop-timeout` (10 s) before SIGTERMing a child that was still loading, which read like a load timeout — issue #21 | ❌ not in the v1.5.2 prebuilt (source builds only) | ❌ not submitted | The router skips the graceful handshake for children that have not finished loading |

## Adding a patch

1. Fix the file inside `engine/src` (the pinned snapshot), then export it:
   ```bash
   cd engine/src
   git diff -- tools/server/server-models.cpp > ../../patches/<name>.patch
   git checkout -- tools/server/server-models.cpp
   ```
2. Confirm it applies at the pinned commit: `git apply --check ../../patches/<name>.patch`.
3. Compile-check it before committing — a patch that does not build stalls every
   source install:
   ```bash
   # reuse the flags CMake generated for that translation unit
   python3 -c "import json,shlex;db=json.load(open('$ENGINE_BUILD/compile_commands.json'));print(next(shlex.split(e['command']) for e in db if e['file'].endswith('tools/server/server-models.cpp')))" > /tmp/flags
   # run the same command with -fsyntax-only against the patched file
   ```
4. Add a row above and link the issue.

## Why these are not upstream yet

Both live in `tools/server`, which upstream refactors often; sending them needs a
reproducer on current upstream `main`, not just on the pinned commit. Until then,
every engine rebuild carries them — see `docs/UPSTREAM_TRACKING.md` §3.
