# Client & UI Integration Guide for Qwen 3.8 27B ROCmFP4

`q38rocm` runs an OpenAI-compatible HTTP API on:
```
http://localhost:8000/v1
```

By default, the server runs **headless/standalone** to maximize available unified RAM for 27B LLM inference (consuming zero extra RAM for web servers). You can optionally connect any desktop client, IDE extension, or browser-based Web UI.

---

## 📑 Supported Frontends & Tools
- [1. Open WebUI (Optional Browser Chat GUI)](#1-open-webui-browser-chat-gui)
- [2. LibreChat](#2-librechat)
- [3. Desktop Web Clients (Chatbox, NextChat, TypingMind)](#3-desktop-clients-chatbox-nextchat-typingmind)
- [4. Continue.dev (VS Code & JetBrains)](#4-continuedev-vs-code--jetbrains)
- [5. Cursor IDE](#5-cursor-ide)
- [6. LiteLLM Proxy](#6-litellm-proxy)
- [7. Pi Coding Agent](#7-pi-coding-agent)

---

## 1. Open WebUI (Browser Chat GUI)

Open WebUI provides a ChatGPT-like browser interface with multi-model switching, document upload (RAG), and user accounts.

### Option A: Via Docker Compose Profile (Recommended)
Run the server with the optional `webui` profile:
```bash
# Starts both qwen38-server (port 8000) and Open WebUI (port 3000)
docker compose --profile webui up -d
```
Open **http://localhost:3000** in your browser.

### Option B: Standalone Open WebUI Docker Container
If `q38rocm` is already running on your host:
```bash
docker run -d -p 3000:8080 \
  --add-host=host.docker.internal:host-gateway \
  -e OPENAI_API_BASE_URL=http://host.docker.internal:8000/v1 \
  -e OPENAI_API_KEY=sk-no-key \
  -v open-webui-data:/app/backend/data \
  --name open-webui \
  --restart unless-stopped \
  ghcr.io/open-webui/open-webui:main
```

### Option C: Connect an Existing Open WebUI Instance
1. In Open WebUI, navigate to **Settings** > **Admin Settings** > **Connections**.
2. Under **OpenAI API**, set:
   - **API Base URL:** `http://localhost:8000/v1` (or `http://host.docker.internal:8000/v1` if in Docker)
   - **API Key:** `sk-no-key`
3. Click **Verify Connection**.
4. Select `qwen38-27b` from the model selector dropdown.

---

## 2. LibreChat

[LibreChat](https://github.com/danny-avila/LibreChat) is an open-source AI chat platform.

Add the following to your `librechat.yaml`:

```yaml
endpoints:
  custom:
    - name: "Qwen 3.8 27B ROCmFP4"
      apiKey: "sk-no-key"
      baseURL: "http://localhost:8000/v1"
      models:
        default: ["qwen38-27b"]
        fetch: true
      titleConvo: true
      modelDisplayLabel: "Qwen 3.8 27B"
```

---

## 3. Desktop Clients (Chatbox, NextChat, TypingMind)

For native desktop apps like **Chatbox**, **NextChat**, **Msty**, or **TypingMind**:

1. Open **Settings** > **Model Provider** > **OpenAI API**.
2. **API Host / Base URL:** `http://localhost:8000` (or `http://localhost:8000/v1`)
3. **API Key:** `sk-no-key`
4. **Model Name:** `qwen38-27b`.

---

## 4. Continue.dev (VS Code & JetBrains)

[Continue.dev](https://continue.dev) connects inline coding assistants to local models.

Add the following to `~/.continue/config.json`:

```json
{
  "models": [
    {
      "title": "Qwen 3.8 27B (Strix Halo ROCmFP4)",
      "provider": "openai",
      "model": "qwen38-27b",
      "apiBase": "http://localhost:8000/v1",
      "apiKey": "sk-no-key",
      "contextLength": 131072,
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

## 5. Cursor IDE

In Cursor Settings:
1. Open **Cursor Settings** > **Models**.
2. Under **OpenAI API Key**, enter `sk-no-key`.
3. Enable **Override OpenAI Base URL** and set:
   ```
   http://localhost:8000/v1
   ```
4. Add model: `qwen38-27b`.

---

## 6. LiteLLM Proxy (Multi-Model Routing)

```yaml
# litellm_config.yaml
model_list:
  - model_name: qwen38-strix
    litellm_params:
      model: openai/qwen38-27b
      api_base: http://localhost:8000/v1
      api_key: sk-no-key
```

Run LiteLLM proxy:
```bash
litellm --config litellm_config.yaml --port 4000
```

---

## 7. Pi Coding Agent

Start the server with bounded context, strict MTP verification, and no hidden prompt checkpoints:

```bash
./run_server.sh --profile agent
```

Add this provider to `~/.pi/agent/models.json`:

```json
{
  "providers": {
    "q38rocm": {
      "baseUrl": "http://127.0.0.1:8000/v1",
      "api": "openai-completions",
      "apiKey": "none",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [
        {
          "id": "qwen38-27b",
          "reasoning": false,
          "contextWindow": 65536,
          "maxTokens": 8192
        }
      ]
    }
  }
}
```

Launch Pi from the exact directory the agent is allowed to inspect:

```bash
cd /path/to/project-or-benchmark/workspace
pi --provider q38rocm --model qwen38-27b
```

For the invoice sandbox benchmark, give Pi the generated `runs/<id>/workspace` directory, not the repository root or your home directory. If tool calls repeat, compare with `./run_server.sh --profile safe` and inspect both Pi JSON events and the server log for connection retries or a GPU reset.
