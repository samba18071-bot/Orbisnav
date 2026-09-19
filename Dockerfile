# ==============================================================================
# OrbisNav Production Vision & Spatial Navigation Server
# High-concurrency WebSocket & Multi-Class Object Detection Container
# ==============================================================================

# Build stage
FROM python:3.11-slim as builder

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY server/requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

# Final runtime stage
FROM python:3.11-slim as runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000 \
    HOST=0.0.0.0 \
    WORKERS=1 \
    LOG_LEVEL=info \
    ORBISNAV_API_KEY=orbisnav-live-key-2026

WORKDIR /app

# Install runtime system dependencies for OpenCV and PyTorch CPU/GPU
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Python packages from builder
COPY --from=builder /install /usr/local

# Copy application server code and model weights
COPY server/ /app/server/
COPY yolov8s-worldv2.pt /app/yolov8s-worldv2.pt
COPY yolov8n_orbisnav.pt /app/yolov8n_orbisnav.pt
COPY yolov8n.pt /app/yolov8n.pt

# Set permissions
RUN chmod -R 755 /app

# Expose standard container port
EXPOSE 8000

# Health check to ensure WebSocket and HTTP availability
HEALTHCHECK --interval=20s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Launch ASGI server with uvloop for low-latency WebSocket streaming
CMD ["uvicorn", "server.main:app", "--host", "0.0.0.0", "--port", "8000", "--loop", "uvloop", "--ws", "websockets", "--ws-ping-interval", "20", "--ws-ping-timeout", "20"]
