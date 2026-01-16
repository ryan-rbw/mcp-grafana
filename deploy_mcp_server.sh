#!/bin/bash
# Production deployment script for MCP Grafana server
# This script deploys the container with auto-restart on failure/reboot
#
# Usage:
#   ./deploy_mcp_server.sh              # Deploy both SSE and HTTP transports
#   ./deploy_mcp_server.sh sse          # Deploy only SSE transport (port 8000)
#   ./deploy_mcp_server.sh http         # Deploy only HTTP transport (port 8001)
#   ./deploy_mcp_server.sh both         # Deploy both (default)
#
# Environment variables:
#   ENABLE_METRICS=true                 # Enable Prometheus metrics at /metrics

set -e

IMAGE="mcp-grafana:latest"
GRAFANA_HOST="graphs.i.kepler.engineering"
GRAFANA_IP="10.240.97.4"

# Ports for each transport
SSE_PORT=8000
HTTP_PORT=8001

# Metrics configuration (set ENABLE_METRICS=true to enable)
ENABLE_METRICS="${ENABLE_METRICS:-false}"

# Load token from environment or file
load_token() {
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
}

# Deploy a single container
deploy_container() {
    local TRANSPORT=$1
    local PORT=$2
    local CONTAINER_NAME="mcp-grafana-${TRANSPORT}"

    if [ "$TRANSPORT" = "sse" ]; then
        ENDPOINT="/sse"
        TRANSPORT_FLAG="sse"
    else
        ENDPOINT="/mcp"
        TRANSPORT_FLAG="streamable-http"
    fi

    echo "Deploying $CONTAINER_NAME (transport: $TRANSPORT_FLAG, port: $PORT, metrics: $ENABLE_METRICS)..."

    # Stop and remove existing container
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true

    # Build command arguments
    local EXTRA_ARGS=""
    if [ "$ENABLE_METRICS" = "true" ]; then
        EXTRA_ARGS="--enable-metrics"
    fi

    # Start new container
    docker run -d \
      --name "$CONTAINER_NAME" \
      --restart=always \
      --network host \
      --add-host "$GRAFANA_HOST:$GRAFANA_IP" \
      -e GRAFANA_URL="https://$GRAFANA_HOST" \
      -e GRAFANA_SERVICE_ACCOUNT_TOKEN="$GRAFANA_SERVICE_ACCOUNT_TOKEN" \
      "$IMAGE" \
      --transport "$TRANSPORT_FLAG" \
      --address "0.0.0.0:$PORT" \
      --tls-skip-verify \
      $EXTRA_ARGS

    sleep 2

    # Health check
    if curl -sf "http://localhost:$PORT/healthz" > /dev/null; then
        echo "  Status: healthy"
        echo "  Endpoint: http://localhost:$PORT$ENDPOINT"
    else
        echo "  Status: FAILED - check logs with: docker logs $CONTAINER_NAME"
    fi
    echo ""
}

# Main
load_token

MODE="${1:-both}"

case "$MODE" in
    sse)
        deploy_container "sse" "$SSE_PORT"
        ;;
    http|mcp)
        deploy_container "http" "$HTTP_PORT"
        ;;
    both|all)
        deploy_container "sse" "$SSE_PORT"
        deploy_container "http" "$HTTP_PORT"
        ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Usage: $0 [sse|http|both]"
        exit 1
        ;;
esac

echo "=== Summary ==="
echo "Containers running:"
docker ps --filter "name=mcp-grafana" --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  None"
echo ""
echo "Endpoints:"
[ "$MODE" = "sse" ] || [ "$MODE" = "both" ] || [ "$MODE" = "all" ] && echo "  SSE (Claude):  http://localhost:$SSE_PORT/sse"
[ "$MODE" = "http" ] || [ "$MODE" = "mcp" ] || [ "$MODE" = "both" ] || [ "$MODE" = "all" ] && echo "  HTTP (Codex):  http://localhost:$HTTP_PORT/mcp"
if [ "$ENABLE_METRICS" = "true" ]; then
    echo ""
    echo "Metrics:"
    [ "$MODE" = "sse" ] || [ "$MODE" = "both" ] || [ "$MODE" = "all" ] && echo "  SSE:           http://localhost:$SSE_PORT/metrics"
    [ "$MODE" = "http" ] || [ "$MODE" = "mcp" ] || [ "$MODE" = "both" ] || [ "$MODE" = "all" ] && echo "  HTTP:          http://localhost:$HTTP_PORT/metrics"
fi
echo ""
echo "Useful commands:"
echo "  View logs:     docker logs -f mcp-grafana-sse"
echo "                 docker logs -f mcp-grafana-http"
echo "  Status:        ./status_mcp_server.sh"
echo "  Stop all:      docker stop mcp-grafana-sse mcp-grafana-http"
