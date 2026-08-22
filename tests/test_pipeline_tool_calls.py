#!/usr/bin/env python3
"""
test_pipeline_tool_calls.py — Regression tests for issue #11.

Verifies that the hybrid NPU pipeline preserves OpenAI tool-calling fields
and bypasses the NPU prefix burst for structured-output requests, so clients
receive standard `message.tool_calls` responses instead of plain-text
<tool_call> markup.
"""

import json
import sys
import unittest
from pathlib import Path

import aiohttp
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))

from run_pipeline import StrixHaloHybridPipeline  # noqa: E402


TOOL_REQUEST = {
    "messages": [{"role": "user", "content": "Use the lookup_weather tool for Shanghai."}],
    "tools": [{
        "type": "function",
        "function": {
            "name": "lookup_weather",
            "description": "look up weather",
            "parameters": {"type": "object", "properties": {"city": {"type": "string"}},
                           "required": ["city"]},
        },
    }],
    "tool_choice": "required",
    "max_tokens": 64,
    "temperature": 0,
}

GPU_TOOL_RESPONSE = {
    "id": "chatcmpl-test",
    "object": "chat.completion",
    "choices": [{
        "index": 0,
        "message": {
            "role": "assistant",
            "content": None,
            "tool_calls": [{
                "id": "call_1",
                "type": "function",
                "function": {"name": "lookup_weather", "arguments": "{\"city\": \"Shanghai\"}"},
            }],
        },
        "finish_reason": "tool_calls",
    }],
}


class FakeSession:
    """Stands in for the upstream HTTP session (NPU + GPU).

    Mirrors aiohttp's `async with session.post(...)` contract."""

    def __init__(self):
        self.gpu_posts = []
        self.npu_posts = 0

    def post(self, url, json=None):
        if "13305" in url:  # NPU drafter
            self.npu_posts += 1
            return _PostCM(_StreamResponse(_npu_sse_chunks()))
        payload = dict(json or {})
        self.gpu_posts.append(payload)
        if payload.get("stream"):
            return _PostCM(_StreamResponse(_gpu_sse_lines("tools" in payload)))
        return _PostCM(_JsonOrStreamResponse(payload))


class _PostCM:
    def __init__(self, resp):
        self.resp = resp

    async def __aenter__(self):
        return self.resp

    async def __aexit__(self, *exc):
        return False


class _JsonOrStreamResponse:
    status = 200

    def __init__(self, request_payload):
        self.request_payload = request_payload

    async def json(self):
        body = dict(GPU_TOOL_RESPONSE)
        # Echo back whether the fields survived reconstruction (issue #11)
        body["_passthrough_tools"] = "tools" in self.request_payload
        body["_passthrough_tool_choice"] = "tool_choice" in self.request_payload
        return body


class _StreamResponse:
    status = 200

    def __init__(self, chunks):
        self._chunks = chunks

    @property
    def content(self):
        return self._iter()

    async def _iter(self):
        for c in self._chunks:
            yield c


def _gpu_sse_lines(request_has_tools=True):
    finish = "tool_calls" if request_has_tools else "stop"
    lines = [
        {"choices": [{"delta": {"role": "assistant"}, "finish_reason": None}]},
        {"choices": [{"delta": {}, "finish_reason": finish}],
         "usage": {"prompt_tokens": 5, "completion_tokens": 3}},
    ]
    out = []
    for l in lines:
        out.append(f"data: {json.dumps(l)}\n\n".encode())
    out.append(b"data: [DONE]\n\n")
    return out


def _npu_sse_chunks():
    out = []
    for tok in ["<tool_call>", "<function=broken>"]:
        chunk = {"choices": [{"delta": {"content": tok}}]}
        out.append(f"data: {json.dumps(chunk)}\n\n".encode())
    return out


class ToolCallPassthroughTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.pipe = StrixHaloHybridPipeline(
            gpu_model_path="/tmp/fake-model.gguf", port=0, gpu_port=18012,
        )
        self.fake = FakeSession()
        self.pipe.http_session = self.fake
        self.pipe.npu_available = True  # force the bug path: NPU *is* available
        self.server = TestServer(self.pipe.app)
        self.client = TestClient(self.server)
        await self.client.start_server()

    async def asyncTearDown(self):
        await self.client.close()

    async def test_nonstream_tool_request_reaches_gpu_intact(self):
        res = await self.client.post("/v1/chat/completions", json={**TOOL_REQUEST, "stream": False})
        body = await res.json()
        self.assertEqual(res.status, 200)
        self.assertTrue(body["choices"][0]["finish_reason"], "tool_calls")
        self.assertTrue(body["_passthrough_tools"], "tools field was dropped")
        self.assertTrue(body["_passthrough_tool_choice"], "tool_choice field was dropped")
        # Structured requests must bypass the NPU drafter entirely (issue #11)
        self.assertEqual(self.fake.npu_posts, 0)

    async def test_stream_tool_request_bypasses_npu_and_preserves_fields(self):
        res = await self.client.post("/v1/chat/completions", json={**TOOL_REQUEST, "stream": True})
        self.assertEqual(res.status, 200)
        raw = await res.read()
        self.assertNotIn(b"<tool_call>", raw, "plain-text tool markup leaked from NPU prefix")
        # The streamed passthrough is the GPU's SSE verbatim; reconstruct payload check:
        self.assertEqual(self.fake.npu_posts, 0, "structured request must not hit the NPU")
        self.assertEqual(len(self.fake.gpu_posts), 1)
        sent = self.fake.gpu_posts[0]
        self.assertIn("tools", sent)
        self.assertIn("tool_choice", sent)

    async def test_plain_stream_still_uses_npu_prefix(self):
        plain = {"messages": [{"role": "user", "content": "hi"}], "stream": True}
        res = await self.client.post("/v1/chat/completions", json=plain)
        self.assertEqual(res.status, 200)
        await res.read()
        self.assertGreaterEqual(self.fake.npu_posts, 1, "non-structured stream should use NPU burst")


if __name__ == "__main__":
    unittest.main()
