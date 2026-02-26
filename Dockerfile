# Stage 1: Build frontend
FROM node:20-slim AS frontend-build
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci --production=false
COPY frontend/ ./
RUN npm run build

# Stage 2: Python relay
FROM python:3.11-slim

WORKDIR /app

# Install minimal system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd -m -u 1000 flowuser

# Install Python dependencies
COPY relay/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy project files
COPY relay/ ./relay/
COPY cadence/ ./cadence/
COPY flow.json ./

# Copy frontend build output
COPY --from=frontend-build /app/frontend/dist ./frontend/dist

# Set proper ownership
RUN chown -R flowuser:flowuser /app

# Switch to non-root user
USER flowuser

# Expose port (Railway sets $PORT dynamically)
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT:-8000}/status || exit 1

# Run the application — use shell form so $PORT is expanded
CMD uvicorn relay.api:app --host 0.0.0.0 --port ${PORT:-8000}
