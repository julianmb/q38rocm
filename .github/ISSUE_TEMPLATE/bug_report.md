---
name: Bug report
about: Report a problem with the engine, server, or scripts
title: '[Bug]: '
labels: bug
---

## Environment

<!-- Engine provenance is the first thing we need: two recent reports (#20, #21)
     cost hours because the binary could not be mapped back to a source revision. -->

```bash
llama-server --version 2>&1 | head -2     # e.g. "version: 215 (12f8b7e)"
cat engine/BUILD_INFO.txt 2>/dev/null
./scripts/strix_diag.sh
```

- Install method: `./build_engine.sh --prebuilt` **or** source build at the pinned commit
- Platform / RAM / UMA framebuffer size:
- ROCm version (`cat /opt/rocm/.info/version`):

## What happened

## What you expected

## Full log

<!-- Attach the COMPLETE server log. A trimmed tail usually starts after the
     interesting part: in issue #21 the decisive line was 40 lines up. -->

## Diagnostics (server / API / networking issues)

Run this while the server is up, **inside the same container or distrobox as the
server** (replace `<port>` and `<model>`), and attach `q38rocm-diag.txt`:

```bash
{
  echo "== which binary =="
  command -v llama-server
  llama-server --version 2>&1 | head -2
  sha256sum "$(command -v llama-server)"

  echo "== who owns the port =="
  (ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null) | grep -E 'LISTEN|<port>'

  echo "== proxy env (curl honours these silently) =="
  env | grep -i proxy || echo "(none)"

  echo "== is llama.cpp the thing answering? =="
  curl -sS -i --noproxy '*' http://127.0.0.1:<port>/health | head -5

  echo "== request trace: method sent + who answered =="
  curl -sv --noproxy '*' -X POST http://127.0.0.1:<port>/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"<model>","messages":[{"role":"user","content":"hi"}],"max_tokens":8}' 2>&1 \
    | grep -E '^(\* Trying|\* Connected|> (GET|POST)|< HTTP|< [Ss]erver)'

  echo "== server state =="
  curl -sS --noproxy '*' http://127.0.0.1:<port>/v1/models
  curl -sS --noproxy '*' http://127.0.0.1:<port>/props
} > q38rocm-diag.txt 2>&1
```

## Checklist

- [ ] I am on the latest `main`
- [ ] I checked `docs/TROUBLESHOOTING.md`
- [ ] The log above is complete, not trimmed
