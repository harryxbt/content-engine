# Content Engine API - Node.js
# TikTok video generation with ffmpeg

FROM node:20-slim

WORKDIR /app

# Install ffmpeg with drawtext support and fonts
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    fonts-dejavu-core \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy package files
COPY package.json ./

# Install Node dependencies
RUN npm install --production

# Copy application code
COPY server.js ./
COPY lib/ ./lib/
COPY fonts/ ./fonts/
COPY library/ ./library/
COPY negatives/ ./negatives/
COPY positives/ ./positives/

# Create output directory
RUN mkdir -p /app/output

# Environment variables
ENV NODE_ENV=production
ENV OUTPUT_DIR=/app/output
ENV LIBRARY_PATH=/app/library
ENV FONT_PATH=/app/fonts/tiktok-sans-scm.ttf
ENV NEG_ROOT=/app/negatives
ENV POS_ROOT=/app/positives

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run
CMD ["node", "server.js"]
