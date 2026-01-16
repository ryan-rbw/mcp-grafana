#!/bin/bash
# Status script for MCP Grafana server(s)

SSE_PORT=8000
HTTP_PORT=8001

check_container() {
    local NAME=$1
    local PORT=$2
    local ENDPOINT=$3

    echo "=== $NAME ==="

    if ! docker inspect "$NAME" &>/dev/null; then
        echo "Status: Not deployed"
        echo ""
        return
    fi

    docker inspect "$NAME" --format='Status:          {{.State.Status}}
Running:         {{.State.Running}}
Started:         {{.State.StartedAt}}
Restart Count:   {{.RestartCount}}
Restart Policy:  {{.HostConfig.RestartPolicy.Name}}'

    # Health check
    if curl -sf "http://localhost:$PORT/healthz" >/dev/null 2>&1; then
        echo "Health:          OK"
        echo "Endpoint:        http://localhost:$PORT$ENDPOINT"
    else
        echo "Health:          FAILED"
    fi
    echo ""
}

echo ""
check_container "mcp-grafana-sse" "$SSE_PORT" "/sse"
check_container "mcp-grafana-http" "$HTTP_PORT" "/mcp"

# Also check for legacy single container
if docker inspect "mcp-grafana-server" &>/dev/null; then
    echo "=== mcp-grafana-server (legacy) ==="
    docker inspect "mcp-grafana-server" --format='Status: {{.State.Status}}'
    echo "Note: Consider migrating to mcp-grafana-sse/mcp-grafana-http"
    echo ""
fi

echo "=== Useful Commands ==="
echo "  Deploy both:   ./deploy_mcp_server.sh"
echo "  Deploy SSE:    ./deploy_mcp_server.sh sse"
echo "  Deploy HTTP:   ./deploy_mcp_server.sh http"
echo "  View logs:     docker logs -f mcp-grafana-sse"
echo "                 docker logs -f mcp-grafana-http"
echo "  Stop all:      docker stop mcp-grafana-sse mcp-grafana-http"
