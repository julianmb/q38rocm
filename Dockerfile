# ==============================================================================
# Dockerfile — Qwen 3.8 27B ROCmFP4 on AMD Hardware (Linux & Windows WSL2)
# Optimized for Mesa RADV Vulkan Wave64 & ROCm / HIP Hardware Acceleration
# ==============================================================================

FROM ubuntu:24.04

LABEL maintainer="ROCmFPX & Strix Halo Open Source Community"
LABEL description="Qwen 3.8 27B ROCmFP4 OpenAI Server on AMD Hardware"

ENV DEBIAN_FRONTEND=noninteractive
ENV HSA_OVERRIDE_GFX_VERSION=11.5.1
ENV GGML_HIP_ENABLE_UNIFIED_MEMORY=1
ENV HIP_VISIBLE_DEVICES=0
ENV ROCM_FLUSH_ACCEPT=1
ENV AMD_VULKAN_ICD=RADV
ENV RADV_PERFTEST="gpl,sam,nggc"
ENV PATH="/app/engine/bin:${PATH}"
ENV LD_LIBRARY_PATH="/app/engine/bin:${LD_LIBRARY_PATH}"

# Bind to all interfaces by default: run_server.sh defaults HOST=127.0.0.1,
# which breaks `docker run -p` port publishing (the in-container healthcheck
# would still pass, masking the problem).
ENV HOST=0.0.0.0

WORKDIR /app

# Install system dependencies & Mesa RADV Vulkan drivers
RUN groupadd render && apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    vulkan-tools \
    mesa-vulkan-drivers \
    libvulkan1 \
    libgomp1 \
    python3 \
    python3-pip \
    tar \
    git \
    findutils \
    && rm -rf /var/lib/apt/lists/*

# Install ROCm 7.2.3 runtime libraries (required by ROCmFPX engine binaries, issue #5).
# ROCmFPX links against libhipblas.so.3 / librocblas.so.5 / libamdhip64.so.7 etc.,
# which are NOT part of a base Ubuntu image. Install only the runtime subset
# (~1.2 GB) instead of the full ~4 GB ROCm toolchain.
RUN curl -fsSL "https://repo.radeon.com/amdgpu-install/7.2.3/ubuntu/noble/amdgpu-install_7.2.3.70203-1_all.deb" -o /tmp/amdgpu-install.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/amdgpu-install.deb \
    && rm -f /tmp/amdgpu-install.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        hip-runtime-amd \
        hipblas \
        rocblas \
        hipblaslt \
        hsa-rocr \
        rocprofiler-register \
        rocsolver \
        roctracer \
        comgr \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV ROCM_HOME=/opt/rocm
ENV LD_LIBRARY_PATH="/opt/rocm/lib:/app/engine/bin:${LD_LIBRARY_PATH}"

# Download and install pre-built ROCmFPX engine binaries
RUN mkdir -p /app/engine && \
    curl -L "https://github.com/julianmb/q38rocm/releases/download/v1.4.0/strix-halo-rocmfpx-engine-v1.4.0-linux-x86_64.tar.gz" -o /tmp/engine.tar.gz && \
    tar -xzf /tmp/engine.tar.gz -C /tmp/ && \
    cp -a /tmp/strix-halo-rocmfpx-engine/* /app/engine/ && \
    rm -rf /tmp/strix-halo-rocmfpx-engine /tmp/engine.tar.gz

# Install Python dependencies
COPY requirements.txt /app/
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt 2>/dev/null || true

# Copy deployment scripts and models directory
COPY . /app/
RUN chmod +x /app/*.sh /app/scripts/*.sh /app/scripts/*.py

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

ENTRYPOINT ["/app/run_server.sh"]
CMD ["/app/models/Qwen3.8-27B-ROCmFP4-FAST.gguf"]
