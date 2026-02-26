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
COPY entrypoint.sh ./

# Copy frontend build output
COPY --from=frontend-build /app/frontend/dist ./frontend/dist

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

# Set proper ownership
RUN chown -R flowuser:flowuser /app

# Switch to non-root user
USER flowuser

EXPOSE 8000

ENTRYPOINT ["/app/entrypoint.sh"]
