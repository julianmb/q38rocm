# Client Integration Guide: Qwen 3.8 27B ROCmFP4 on AMD Strix Halo

This guide demonstrates how to connect third-party developer tools and Web UIs to the high-performance `llama-server` running on AMD Strix Halo.

The server provides a standard OpenAI-compatible API endpoint at:
```
http://localhost:8000/v1
```

---

## 1. Open WebUI

[Open WebUI](https://github.com/open-webui/open-webui) is a full-featured web interface for local and remote LLMs.

### Setup Steps:
1. In Open WebUI, navigate to **Settings** > **Admin Settings** > **Connections**.
2. Under **OpenAI API**, set:
   - **API Base URL:** `http://localhost:8000/v1` (or `http://host.docker.internal:8000/v1` if running Open WebUI in Docker)
   - **API Key:** `sk-no-key`
3. Click **Verify Connection**.
4. In the model dropdown on the main chat page, select `qwen38-27b` (or `Qwen3.8-27B-ROCmFP4-FAST`).

---

## 2. Continue.dev (VS Code / JetBrains Code Assistant)

[Continue](https://continue.dev) is an open-source AI code assistant that integrates directly into VS Code and JetBrains IDEs.

Add the following to your `~/.continue/config.json`:

```json
{
  "models": [
    {
      "title": "Qwen 3.8 27B (Strix Halo ROCmFP4)",
      "provider": "openai",
      "model": "qwen38-27b",
      "apiBase": "http://localhost:8000/v1",
      "apiKey": "sk-no-key",
      "contextLength": 32768,
      "roles": ["chat", "edit"]
    }
  ],
  "tabAutocompleteModel": {
    "title": "Qwen 3.8 27B Autocomplete",
    "provider": "openai",
    "model": "qwen38-27b",
    "apiBase": "http://localhost:8000/v1",
    "apiKey": "sk-no-key"
  }
}
```

---

## 3. Cursor IDE

In Cursor Settings:
1. Open **Cursor Settings** > **Models**.
2. Under **OpenAI API Key**, enter `sk-no-key`.
3. Enable **Override OpenAI Base URL** and enter:
   ```
   http://localhost:8000/v1
   ```
4. Add model name: `qwen38-27b`.

---

## 4. Python OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="sk-no-key"
)

response = client.chat.completions.create(
    model="qwen38-27b",
    messages=[
        {"role": "system", "content": "You are an expert systems programmer."},
        {"role": "user", "content": "Write an asynchronous token queue in Rust using tokio channels."}
    ],
    temperature=0.7,
    max_tokens=500
)

print(response.choices[0].message.content)
```

---

## 5. LiteLLM Proxy

To proxy multiple local and remote models with unified rate limiting and logging:

```yaml
# config.yaml
model_list:
  - model_name: qwen38-strix
    litellm_params:
      model: openai/qwen38-27b
      api_base: http://localhost:8000/v1
      api_key: sk-no-key
```

Run proxy:
```bash
litellm --config config.yaml --port 4000
```
