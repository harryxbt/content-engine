# Content Engine API - Docker Image
# Optimized for Render, Fly.io, Railway, and other container platforms

FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies for Pillow and MoviePy (ffmpeg)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg62-turbo-dev \
    zlib1g-dev \
    libpng-dev \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first (layer caching)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY content_engine/ ./content_engine/
COPY api/ ./api/
COPY fonts/ ./fonts/
COPY negatives/ ./negatives/
COPY positives/ ./positives/
COPY library/ ./library/

# Create output directory
RUN mkdir -p /app/output

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV NEG_ROOT=/app/negatives
ENV POS_ROOT=/app/positives
ENV OUTPUT_DIR=/app/output
ENV FONT_PATH=/app/fonts/tiktok-sans-scm.ttf
ENV LIBRARY_PATH=/app/library

# Expose port (Render uses PORT env var)
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Run the application
# Render sets PORT env var, default to 8000
CMD uvicorn api.main:app --host 0.0.0.0 --port ${PORT:-8000}
