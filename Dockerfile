# ==============================================================================
# Dockerfile — Qwen 3.8 27B ROCmFP4 on AMD Strix Halo (Ryzen AI Max+ 395)
# Optimized for Mesa RADV Vulkan Wave64 & ROCm / HIP Hardware Passthrough
# ==============================================================================

FROM ubuntu:24.04

LABEL maintainer="ROCmFPX & Strix Halo Open Source Community"
LABEL description="Qwen 3.8 27B ROCmFP4 OpenAI Server on AMD Strix Halo"

ENV DEBIAN_FRONTEND=noninteractive
ENV HSA_OVERRIDE_GFX_VERSION=11.5.1
ENV GGML_HIP_ENABLE_UNIFIED_MEMORY=1
ENV HIP_VISIBLE_DEVICES=0
ENV ROCM_FLUSH_ACCEPT=1
ENV AMD_VULKAN_ICD=RADV
ENV VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
ENV RADV_PERFTEST="gpl,sam,nggc"
ENV PATH="/app/engine/bin:${PATH}"
ENV LD_LIBRARY_PATH="/app/engine/bin:${LD_LIBRARY_PATH}"

WORKDIR /app

# Install system dependencies & Mesa RADV Vulkan drivers
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    vulkan-tools \
    mesa-vulkan-drivers \
    libvulkan1 \
    libgomp1 \
    python3 \
    python3-pip \
    tar \
    && rm -rf /var/lib/apt/lists/*

# Download and install pre-built ROCmFPX engine binaries (v1.0.0)
RUN mkdir -p /app/engine && \
    curl -L "https://github.com/julianmb/q38rocm/releases/download/v1.0.0/strix-halo-rocmfpx-engine-v1.0.0-linux-x86_64.tar.gz" -o /tmp/engine.tar.gz && \
    tar -xzf /tmp/engine.tar.gz -C /tmp/ && \
    cp -a /tmp/strix-halo-rocmfpx-engine/* /app/engine/ && \
    rm -rf /tmp/strix-halo-rocmfpx-engine /tmp/engine.tar.gz

# Copy deployment scripts and models directory
COPY . /app/
RUN chmod +x /app/*.sh /app/scripts/*.sh /app/scripts/*.py

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

ENTRYPOINT ["/app/run_server.sh"]
CMD ["/app/models/Qwen3.8-27B-ROCmFP4-FAST.gguf"]
