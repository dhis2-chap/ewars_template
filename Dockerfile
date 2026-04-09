# Stage 1: Install Python dependencies
FROM --platform=linux/amd64 ghcr.io/astral-sh/uv:0.9-python3.13-bookworm-slim AS python-builder
WORKDIR /build
COPY pyproject.toml ./
RUN uv sync --no-dev

# Stage 2: Runtime with R (INLA) + Python (chapkit)
FROM --platform=linux/amd64 ghcr.io/dhis2-chap/docker_r_inla:master

# Install Python 3.13
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    curl \
    && curl -fsSL https://raw.githubusercontent.com/deadsnakes/issues/master/README.md > /dev/null 2>&1 || true \
    && add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null \
    || (echo "deb http://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu jammy main" >> /etc/apt/sources.list.d/deadsnakes.list \
        && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys F23C5A6CF475977595C89F51BA6932366A755776) \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    python3.13 \
    python3.13-venv \
    python3.13-dev \
    && ln -sf /usr/bin/python3.13 /usr/local/bin/python \
    && ln -sf /usr/bin/python3.13 /usr/local/bin/python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Python virtual environment from builder
COPY --from=python-builder /build/.venv /app/.venv
ENV PATH="/app/.venv/bin:/usr/local/bin:$PATH"
ENV VIRTUAL_ENV="/app/.venv"

# Copy application files
COPY main.py pyproject.toml ./
COPY scripts/ ./scripts/

EXPOSE 8000

CMD ["python3.13", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
