# Docker Deployment Guide for Qwen 3.8 27B ROCmFP4

Run Qwen 3.8 27B ROCmFP4 inside a container with AMD GPU acceleration on **Linux** and **Windows (WSL2 / Docker Desktop)**.

---

## 1. Windows Setup (Docker Desktop + WSL2)

You can run this container on Windows with full AMD GPU hardware acceleration using Docker Desktop's WSL2 backend.

### 1.1 Prerequisites on Windows:
1. **AMD Graphics Driver:** Install the latest [AMD Adrenalin Software](https://www.amd.com/en/support) for Windows (enables GPU compute passthrough to WSL2).
2. **Docker Desktop:** Ensure **Settings** > **General** > **Use the WSL 2 based engine** is checked.
3. **WSL2 Distro:** Open your WSL2 terminal (e.g. Ubuntu on Windows):
   ```bash
   # Verify AMD GPU device nodes are visible in WSL2:
   ls -la /dev/kfd /dev/dri
   ```

### 1.2 Start Container on Windows WSL2:
```bash
git clone https://github.com/julianmb/q38rocm.git
cd q38rocm

# Option A: Standalone Server (Port 8000)
docker compose up -d

# Option B: Server + Open WebUI Chat Browser (Port 3000)
docker compose --profile webui up -d
```

---

## 2. Linux Setup (Ubuntu / Fedora / Arch)

### 2.1 Add User to GPU Groups:
```bash
sudo usermod -aG video,render $USER
```

### 2.2 Start via Docker Compose:
```bash
# Standalone Server
docker compose up -d

# With Open WebUI
docker compose --profile webui up -d
```

---

## 3. Direct `docker run` Command

If launching directly without Docker Compose:

```bash
docker run -d \
  --name qwen38-server \
  -p 8000:8000 \
  --device=/dev/kfd \
  --device=/dev/dri \
  --group-add video \
  --group-add render \
  --ipc=host \
  -v $(pwd)/models:/app/models \
  -v ~/.cache/huggingface/hub:/root/.cache/huggingface/hub \
  --restart unless-stopped \
  ghcr.io/julianmb/q38rocm:latest
```

---

## 4. Endpoints

* **OpenAI API:** `http://localhost:8000/v1`
* **Health Check:** `http://localhost:8000/health`
* **Open WebUI (if enabled):** `http://localhost:3000`
