# =============================================================================
# Multi-stage Dockerfile — FastAPI Application
# Stage 1: Build dependencies
# Stage 2: Minimal production image (non-root, hardened)
# =============================================================================

# ------- Stage 1: Builder -------
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY app/requirements.txt .

# Install to a local directory for clean copy into final stage
RUN pip install --upgrade pip \
    && pip install --prefix=/install --no-cache-dir -r requirements.txt


# ------- Stage 2: Production image -------
FROM python:3.11-slim AS production

ARG BUILD_DATE
ARG GIT_COMMIT

LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.title="fastapi-app"
LABEL maintainer="Prasanth Bugga <prasaanthbugga21@gmail.com>"

# Install runtime-only system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder stage
COPY --from=builder /install /usr/local

WORKDIR /app

# Create a non-root user and group for security
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --shell /bin/bash --create-home appuser

# Copy application source
COPY app/ .

# Set correct ownership
RUN chown -R appuser:appgroup /app

# Drop to non-root user
USER appuser

# Expose application port
EXPOSE 8000

# Pass build metadata as environment variables
ENV GIT_COMMIT=${GIT_COMMIT}
ENV APP_VERSION=${BUILD_DATE}

# Health check for Docker and container runtimes
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl --fail http://localhost:8000/healthz/live || exit 1

# Production entrypoint — Gunicorn with Uvicorn workers
CMD ["gunicorn", "main:app", \
    "--workers", "4", \
    "--worker-class", "uvicorn.workers.UvicornWorker", \
    "--bind", "0.0.0.0:8000", \
    "--timeout", "60", \
    "--graceful-timeout", "30", \
    "--access-logfile", "-", \
    "--error-logfile", "-"]
