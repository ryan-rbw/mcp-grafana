#!/bin/bash
# Production deployment script for MCP Grafana server
# This script deploys the container with auto-restart on failure/reboot

set -e

CONTAINER_NAME="mcp-grafana-server"
IMAGE="mcp-grafana:latest"
GRAFANA_HOST="graphs.i.kepler.engineering"
GRAFANA_IP="10.240.97.4"
LISTEN_ADDRESS="0.0.0.0:8000"

# Transport type: "sse" or "streamable-http"
# - sse: Server-Sent Events, endpoint at /sse (Claude Desktop, Claude Code CLI)
# - streamable-http: HTTP streaming, endpoint at /mcp (Codex CLI, newer clients)
TRANSPORT="${TRANSPORT:-streamable-http}"

# Load token from environment or file
# Option 1: Set GRAFANA_SERVICE_ACCOUNT_TOKEN in environment before running
# Option 2: Create /etc/mcp-grafana/token with the token value
if [ -z "$GRAFANA_SERVICE_ACCOUNT_TOKEN" ]; then
    TOKEN_FILE="/etc/mcp-grafana/token"
    if [ -f "$TOKEN_FILE" ]; then
        GRAFANA_SERVICE_ACCOUNT_TOKEN=$(cat "$TOKEN_FILE")
    else
        echo "Error: GRAFANA_SERVICE_ACCOUNT_TOKEN not set and $TOKEN_FILE not found"
        echo "Either export GRAFANA_SERVICE_ACCOUNT_TOKEN or create $TOKEN_FILE"
        exit 1
    fi
fi

echo "Stopping existing container (if running)..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

echo "Starting MCP Grafana server (transport: $TRANSPORT)..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart=always \
  --network host \
  --add-host "$GRAFANA_HOST:$GRAFANA_IP" \
  -e GRAFANA_URL="https://$GRAFANA_HOST" \
  -e GRAFANA_SERVICE_ACCOUNT_TOKEN="$GRAFANA_SERVICE_ACCOUNT_TOKEN" \
  "$IMAGE" \
  --transport "$TRANSPORT" \
  --address "$LISTEN_ADDRESS" \
  --tls-skip-verify

echo "Waiting for startup..."
sleep 2

# Determine endpoint based on transport
if [ "$TRANSPORT" = "sse" ]; then
    ENDPOINT="/sse"
else
    ENDPOINT="/mcp"
fi

# Health check
if curl -sf http://localhost:8000/healthz > /dev/null; then
    echo "MCP Grafana server is running and healthy"
    echo "Endpoint: http://localhost:8000$ENDPOINT"
else
    echo "Warning: Health check failed. Check logs with: docker logs $CONTAINER_NAME"
fi

echo ""
echo "Useful commands:"
echo "  View logs:     docker logs -f $CONTAINER_NAME"
echo "  Stop:          docker stop $CONTAINER_NAME"
echo "  Restart:       docker restart $CONTAINER_NAME"
