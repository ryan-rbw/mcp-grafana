#!/bin/bash
# Status script for MCP Grafana server

CONTAINER_NAME="mcp-grafana-server"

echo "=== MCP Grafana Server Status ==="
echo ""

# Check if container exists
if ! docker inspect "$CONTAINER_NAME" &>/dev/null; then
    echo "Container '$CONTAINER_NAME' not found."
    echo "Run ./deploy_mcp_server.sh to start it."
    exit 1
fi

# Get container details
docker inspect "$CONTAINER_NAME" --format='
Container:       {{.Name}}
Image:           {{.Config.Image}}
Status:          {{.State.Status}}
Running:         {{.State.Running}}
Started:         {{.State.StartedAt}}
Restart Count:   {{.RestartCount}}
Restart Policy:  {{.HostConfig.RestartPolicy.Name}}
'

echo "=== Health Check ==="
if curl -sf http://localhost:8000/healthz >/dev/null 2>&1; then
    echo "Health: OK"
else
    echo "Health: FAILED (server not responding)"
fi

echo ""
echo "=== Recent Logs (last 10 lines) ==="
docker logs --tail 10 "$CONTAINER_NAME" 2>&1

echo ""
echo "=== Useful Commands ==="
echo "  View full logs:    docker logs -f $CONTAINER_NAME"
echo "  Restart:           docker restart $CONTAINER_NAME"
echo "  Stop:              docker stop $CONTAINER_NAME"
echo "  Redeploy:          ./deploy_mcp_server.sh"
