# Content Engine API - Node.js
# TikTok video generation with ffmpeg

FROM node:20-slim

WORKDIR /app

# Install curl, ca-certificates for HTTPS, and fonts
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    xz-utils \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Install static ffmpeg build (full codec support)
RUN curl -L https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz -o /tmp/ffmpeg.tar.xz \
    && tar -xf /tmp/ffmpeg.tar.xz -C /tmp \
    && mv /tmp/ffmpeg-*-amd64-static/ffmpeg /usr/local/bin/ \
    && mv /tmp/ffmpeg-*-amd64-static/ffprobe /usr/local/bin/ \
    && rm -rf /tmp/ffmpeg* \
    && chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe

# Copy package files
COPY package.json ./

# Install Node dependencies
RUN npm install --production

# Copy application code
COPY server.js ./
COPY lib/ ./lib/
COPY fonts/ ./fonts/
COPY library/ ./library/

# Create output directory
RUN mkdir -p /app/output

# Environment variables
ENV NODE_ENV=production
ENV OUTPUT_DIR=/app/output
ENV LIBRARY_PATH=/app/library
ENV FONT_PATH=/app/fonts/tiktok-sans-scm.ttf

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run
CMD ["node", "server.js"]
