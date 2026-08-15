# OpenAI-Compatible REST API Reference

The `llama-server` runtime for Qwen 3.8 27B ROCmFP4 exposes an OpenAI-compatible HTTP REST API on `http://localhost:8000`.

---

## 1. Chat Completions (`POST /v1/chat/completions`)

Generates a completion for a given prompt or multi-turn conversation.

### Request Headers
```http
Content-Type: application/json
Authorization: Bearer sk-no-key (optional)
```

### Request Body Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `model` | string | `"qwen38-27b"` | Model identifier |
| `messages` | array | *required* | List of message objects (`role`, `content`) |
| `temperature` | float | `0.7` | Sampling temperature (0.0 for deterministic greedy) |
| `top_p` | float | `0.8` | Nucleus sampling probability threshold |
| `top_k` | integer | `20` | Top-K sampling threshold |
| `max_tokens` | integer | `4096` | Maximum generation tokens |
| `stream` | boolean | `false` | Enable Server-Sent Events (SSE) streaming |
| `presence_penalty`| float | `1.5` | Presence penalty to prevent repetition |
| `stop` | array | `null` | Custom stop sequence strings |

### Example Request (`curl`)
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen38-27b",
    "messages": [
      {
        "role": "system",
        "content": "Reasoning effort is set to xhigh. Please think carefully through the task."
      },
      {
        "role": "user",
        "content": "Write a complete binary search tree in Rust with insert and search methods."
      }
    ],
    "temperature": 0.0,
    "max_tokens": 500
  }'
```

### Example Response Schema
```json
{
  "id": "chatcmpl-9f8a2b3c",
  "object": "chat.completion",
  "created": 1723789200,
  "model": "qwen38-27b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "```rust\n#[derive(Debug)]\npub struct Node<T> {\n    pub val: T,\n    pub left: Option<Box<Node<T>>>,\n    pub right: Option<Box<Node<T>>>,\n}\n..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 42,
    "completion_tokens": 248,
    "total_tokens": 290
  },
  "timings": {
    "prompt_n": 42,
    "prompt_ms": 439.4,
    "prompt_per_second": 95.58,
    "predicted_n": 248,
    "predicted_ms": 7118.2,
    "predicted_per_second": 34.84,
    "draft_n": 182,
    "draft_n_accepted": 149
  }
}
```

---

## 2. Streaming Chat (`POST /v1/chat/completions` with `"stream": true`)

Streams tokens via Server-Sent Events (`text/event-stream`).

```bash
curl -N -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen38-27b",
    "messages": [{"role": "user", "content": "Explain Strix Halo architecture."}],
    "stream": true
  }'
```

---

## 3. Server Health & Readiness (`GET /health`)

Checks if the server is healthy and model weights are resident in unified memory.

```bash
curl http://localhost:8000/health
```

**Response:**
```json
{
  "status": "ok",
  "slots_idle": 1,
  "slots_processing": 0
}
```

---

## 4. Active Slot & Speculative Telemetry (`GET /slots`)

Retrieves real-time execution statistics, KV cache memory allocation, and draft acceptance ratios.

```bash
curl http://localhost:8000/slots
```

---

## 5. Model Information (`GET /v1/models`)

Lists available registered models.

```bash
curl http://localhost:8000/v1/models
```

**Response:**
```json
{
  "object": "list",
  "data": [
    {
      "id": "qwen38-27b",
      "object": "model",
      "created": 1723789200,
      "owned_by": "llamacpp"
    }
  ]
}
```
