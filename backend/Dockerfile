# ── Stage 1: builder ─────────────────────────────────────────────────────────
# gcc and libpq-dev are needed to compile psycopg2 from source.
# They are installed here and go no further than this stage.
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/install -r requirements.txt

# ── Stage 2: runtime ─────────────────────────────────────────────────────────
# Fresh base image — no build tools, no compiler, no libpq-dev.
FROM python:3.11-slim

# curl is the only system package needed at runtime (HEALTHCHECK).
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Pull in compiled Python packages from the builder stage.
COPY --from=builder /install /install
ENV PYTHONPATH=/install

WORKDIR /app
COPY . .

RUN adduser --disabled-password --gecos "" appuser
USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1

CMD ["python", "-m", "gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "app:app"]
