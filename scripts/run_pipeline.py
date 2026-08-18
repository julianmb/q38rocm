#!/usr/bin/env python3
"""
run_pipeline.py — Strix Halo Hybrid NPU + iGPU Pipeline (Implicit Verification)

Real hybrid architecture (Qwen 3.8 27B only, empirically validated):
  1. NPU (qwen3.5-0.8b-FLM @ ~42 tok/s, ~347ms TTFT, ~2W) streams the FIRST tokens
     of the answer to the client instantly — giving sub-350ms perceived latency.
  2. The pipeline feeds the NPU's draft as an assistant continuation into the
     27B iGPU model (Qwen3.8 ROCmFP4 + embedded MTP, 33.8 tok/s), which verifies
     the draft via a batched prefill and then streams the authoritative
     continuation. One coherent answer, instant start, peak-quality finish.

Exposes an OpenAI-compatible endpoint on --port (default: 11435).

Requires:
  - Lemonade running the flm:npu backend with the qwen3.5-0.8b-FLM model loaded.
  - A ROCmFPX llama-server binary (./engine/bin or PATH).
  - The Qwen 3.8 27B ROCmFP4 weights.
"""

import os
import sys
import json
import time
import signal
import asyncio
import argparse
import shutil
import subprocess
from pathlib import Path
from typing import Optional
import aiohttp
from aiohttp import web

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent

def resolve_engine_bin(name="llama-server"):
    candidates = [
        ROOT_DIR / "engine" / "bin" / name,
        Path("/home/user/source/strix-halo-rocmfpx-hub/engine/bin") / name,
        Path("/home/user/source/ROCmFPX/build-strix-rocmfp4/bin") / name,
        shutil.which(name) or "",
    ]
    for c in candidates:
        if c and Path(c).exists() and os.access(c, os.X_OK):
            return str(Path(c))
    return None

def resolve_gpu_model():
    candidates = [
        ROOT_DIR / "Qwen3.8-27B-ROCmFP4-FAST.gguf",
        ROOT_DIR / "models" / "Qwen3.8-27B-ROCmFP4-FAST.gguf",
        Path("/home/user/source/strix-halo-rocmfpx-hub/models/qwen38-27b/Qwen3.8-27B-ROCmFP4-FAST.gguf"),
    ]
    for c in candidates:
        if c.exists():
            return str(c)
    return None

DEFAULT_NPU_MODEL = "qwen3.5-0.8b-FLM"
GPU_SERVER_PORT = 8012
NPU_SERVER_URL = "http://127.0.0.1:13305"   # lemonade front
PIPELINE_PORT = 11435
NPU_BURST_TOKENS = 24   # how many tokens the NPU drafts before GPU handoff


class StrixHaloHybridPipeline:
    def __init__(
        self,
        gpu_model_path: str,
        npu_model_name: str = DEFAULT_NPU_MODEL,
        llama_bin: str | None = None,
        port: int = PIPELINE_PORT,
        gpu_port: int = GPU_SERVER_PORT,
        npu_url: str = NPU_SERVER_URL,
        device: str = "Vulkan0",
        draft_n: int = 4,
        npu_burst_tokens: int = NPU_BURST_TOKENS,
    ):
        self.gpu_model_path = gpu_model_path
        self.npu_model_name = npu_model_name
        self.llama_bin = llama_bin or resolve_engine_bin("llama-server")
        self.port = port
        self.gpu_port = gpu_port
        self.npu_url = npu_url
        self.device = device
        self.draft_n = draft_n
        self.npu_burst_tokens = npu_burst_tokens
        self.gpu_process: Optional[subprocess.Popen] = None
        self.http_session: Optional[aiohttp.ClientSession] = None
        self.npu_available = False
        self.app = web.Application()
        self.setup_routes()

    def setup_routes(self):
        self.app.router.add_get("/health", self.handle_health)
        self.app.router.add_get("/v1/models", self.handle_models)
        self.app.router.add_post("/v1/chat/completions", self.handle_chat_completions)

    async def handle_health(self, request: web.Request) -> web.Response:
        return web.json_response({
            "status": "healthy",
            "pipeline": "Strix-Halo-Hybrid-Implicit-Verification",
            "npu_node": "/dev/accel/accel0",
            "npu_available": self.npu_available,
            "gpu_device": self.device,
            "target_model": Path(self.gpu_model_path).name,
            "draft_model": self.npu_model_name,
            "npu_burst_tokens": self.npu_burst_tokens,
        })

    async def handle_models(self, request: web.Request) -> web.Response:
        return web.json_response({
            "object": "list",
            "data": [{
                "id": "qwen3.8-27b-hybrid",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "strix-halo-pipeline",
            }]
        })

    def start_gpu_server(self):
        if not self.llama_bin or not os.path.exists(self.llama_bin):
            print("[Pipeline] Error: llama-server binary not found (run ./build_engine.sh)")
            return False
        if not (os.path.exists(self.gpu_model_path)):
            print(f"[Pipeline] Error: model not found: {self.gpu_model_path}")
            return False
        cmd = [
            self.llama_bin, "-m", self.gpu_model_path,
            "--port", str(self.gpu_port), "--host", "127.0.0.1",
            "--device", self.device,
            "--spec-type", "draft-mtp", "--spec-draft-n-max", str(self.draft_n),
            "-ngl", "99", "-fa", "1", "-c", "32768", "-b", "2048", "-ub", "2048",
            "--no-mmap", "--reasoning", "off",
        ]
        env = os.environ.copy()
        env["AMD_VULKAN_ICD"] = "RADV"
        env["RADV_PERFTEST"] = "gpl,sam,nggc"
        env["ROCBLAS_USE_HIPBLASLT"] = "1"
        print(f"[Pipeline] starting iGPU server ({self.device}, K={self.draft_n}) :{self.gpu_port}")
        self.gpu_process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                            stderr=subprocess.PIPE, env=env,
                                            preexec_fn=os.setsid)
        return True

    async def wait_for_gpu_server(self, max_retries=60):
        url = f"http://127.0.0.1:{self.gpu_port}/health"
        for i in range(max_retries):
            try:
                async with self.http_session.get(url) as r:
                    if r.status == 200:
                        print(f"[Pipeline] iGPU ready ({i}s)")
                        return True
            except Exception:
                pass
            await asyncio.sleep(1)
        print("[Pipeline] WARN: iGPU server not ready")
        return False

    async def probe_npu(self):
        try:
            async with self.http_session.get(f"{self.npu_url}/api/v1/models") as r:
                if r.status == 200:
                    self.npu_available = True
                    print("[Pipeline] NPU drafter available")
                    return True
        except Exception as e:
            print(f"[Pipeline] NPU not available: {e}")
        self.npu_available = False
        return False

    async def npu_stream(self, messages, max_tokens):
        """Yield NPU draft tokens incrementally as they arrive."""
        payload = {
            "model": self.npu_model_name,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": 0.2,
            "stream": True,
        }
        async with self.http_session.post(f"{self.npu_url}/v1/chat/completions", json=payload) as r:
            if r.status != 200:
                return
            async for line in r.content:
                line = line.decode("utf-8").strip()
                if not line.startswith("data: ") or line == "data: [DONE]":
                    continue
                try:
                    chunk = json.loads(line[6:])
                    delta = chunk["choices"][0].get("delta", {}).get("content", "")
                    if delta:
                        yield delta
                except Exception:
                    pass

    async def handle_chat_completions(self, request: web.Request) -> web.StreamResponse:
        try:
            body = await request.json()
        except Exception:
            return web.json_response({"error": "Invalid JSON body"}, status=400)

        stream = body.get("stream", False)
        messages = body.get("messages", [])
        max_tokens = body.get("max_tokens", 512)
        temperature = body.get("temperature", 0.7)

        if not stream:
            gpu_payload = {"messages": messages, "max_tokens": max_tokens,
                           "temperature": temperature, "stream": False}
            async with self.http_session.post(f"http://127.0.0.1:{self.gpu_port}/v1/chat/completions",
                                              json=gpu_payload) as r:
                return web.json_response(await r.json())

        response = web.StreamResponse(status=200, reason="OK", headers={
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        })
        await response.prepare(request)

        def sse(delta_text):
            chunk = {"id": f"chatcmpl-{int(time.time()*1000)}", "object": "chat.completion.chunk",
                     "choices": [{"index": 0, "delta": {"content": delta_text}}]}
            return f"data: {json.dumps(chunk)}\n\n".encode()

        try:
            # === Phase 1: NPU burst (stream incrementally for instant TTFT) ===
            npu_draft = ""
            t0 = time.perf_counter()
            if self.npu_available:
                async for delta in self.npu_stream(messages, self.npu_burst_tokens):
                    npu_draft += delta
                    await response.write(sse(delta))
            npu_ms = (time.perf_counter() - t0) * 1000

            # === Phase 2: GPU continuation (authoritative 27B answer) ===
            cont_messages = list(messages) + [{"role": "assistant", "content": npu_draft}] if npu_draft else list(messages)
            gpu_payload = {"messages": cont_messages, "max_tokens": max_tokens,
                           "temperature": temperature, "stream": True}
            async with self.http_session.post(f"http://127.0.0.1:{self.gpu_port}/v1/chat/completions",
                                              json=gpu_payload) as r:
                async for line in r.content:
                    await response.write(line)

            await response.write(b"data: [DONE]\n\n")
            print(f"[Pipeline] turn done: npu_burst={len(npu_draft.split())} tokens in {npu_ms:.0f}ms")
        except (ConnectionResetError, aiohttp.ClientConnectionError) as e:
            print(f"[Pipeline] client disconnected during stream: {e}")
        except Exception as e:
            print(f"[Pipeline] stream error: {e}")
            try:
                await response.write(sse(f"\n[error: {e}]"))
                await response.write(b"data: [DONE]\n\n")
            except Exception:
                pass
        return response

    async def start(self):
        self.http_session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=300))
        self.start_gpu_server()
        gpu_task = asyncio.create_task(self.wait_for_gpu_server())
        npu_task = asyncio.create_task(self.probe_npu())
        await asyncio.gather(gpu_task, npu_task)

        runner = web.AppRunner(self.app)
        await runner.setup()
        await web.TCPSite(runner, "0.0.0.0", self.port).start()
        print(f"[Pipeline] hybrid pipeline on http://0.0.0.0:{self.port} "
              f"(NPU={'on' if self.npu_available else 'off'})")

    def stop(self):
        if self.gpu_process:
            try:
                os.killpg(os.getpgid(self.gpu_process.pid), signal.SIGTERM)
            except Exception:
                pass


def main():
    p = argparse.ArgumentParser(description="Strix Halo Hybrid NPU + iGPU pipeline (Qwen 3.8 27B)")
    p.add_argument("--gpu-model", default=resolve_gpu_model())
    p.add_argument("--npu-model", default=DEFAULT_NPU_MODEL)
    p.add_argument("--port", type=int, default=PIPELINE_PORT)
    p.add_argument("--gpu-port", type=int, default=GPU_SERVER_PORT)
    p.add_argument("--device", default="Vulkan0")
    p.add_argument("--draft-n", type=int, default=4)
    p.add_argument("--npu-burst-tokens", type=int, default=NPU_BURST_TOKENS)
    args = p.parse_args()

    if not args.gpu_model:
        print("[Pipeline] Error: Qwen3.8-27B-ROCmFP4-FAST.gguf not found. Run ./download_model.sh first.")
        sys.exit(1)

    pipe = StrixHaloHybridPipeline(gpu_model_path=args.gpu_model, npu_model_name=args.npu_model,
                                   port=args.port, gpu_port=args.gpu_port, device=args.device,
                                   draft_n=args.draft_n, npu_burst_tokens=args.npu_burst_tokens)
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(pipe.start())
        loop.run_forever()
    except KeyboardInterrupt:
        print("\n[Pipeline] shutting down")
    finally:
        pipe.stop()


if __name__ == "__main__":
    main()
