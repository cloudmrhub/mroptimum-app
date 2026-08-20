FROM python:3.10-slim

WORKDIR /app

# Install system deps
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Python deps (copy just requirements first for better layer caching)
COPY worker/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Copy the calculation source (app.py — the core compute logic)
COPY calculation/src/app.py /app/app.py

# Copy worker service
COPY worker/main.py /app/main.py

# Matplotlib config (headless)
RUN mkdir -p /tmp/.matplotlib && chmod 777 /tmp/.matplotlib
ENV MPLCONFIGDIR=/tmp/.matplotlib
ENV PYTHONUNBUFFERED=1

EXPOSE 8000

ENTRYPOINT ["python", "main.py"]
