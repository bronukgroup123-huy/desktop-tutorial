# ============================================================================
# Dockerfile for Python API (FastAPI) — Multi-Stage
# ============================================================================

# ===== BUILD STAGE =====
FROM python:3.12-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install to user site-packages
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ===== RUNTIME STAGE =====
FROM python:3.12-alpine

WORKDIR /app

# Install runtime dependencies (postgresql client for healthchecks/migrations)
RUN apk add --no-cache libpq

# Create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Copy installed packages from builder
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY --chown=appuser:appgroup . .

ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER appuser

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]