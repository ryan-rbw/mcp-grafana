# Deployment Guide

This document covers deploying the MCP Grafana server and documents additions made in this fork.

## Fork Additions

This fork adds the following features on top of [grafana/mcp-grafana](https://github.com/grafana/mcp-grafana):

### PostgreSQL/TimescaleDB Tools

A new `query_postgres` tool for executing raw SQL queries against PostgreSQL and TimescaleDB datasources.

**Tool:** `query_postgres`
- **Parameters:**
  - `datasourceUid` (required): The UID of the PostgreSQL/TimescaleDB datasource
  - `rawSql` (required): The raw SQL query to execute
  - `format` (optional): Response format, defaults to `table`

**Enable/Disable:**
```bash
# Enabled by default. To disable:
./mcp-grafana --disable-postgres
```

**Required Grafana Permissions:**
- `datasources:query` on the target datasource

---

## Production Deployment

### Prerequisites

1. Docker installed on the target server
2. A Grafana service account token with appropriate permissions
3. Network access from the server to your Grafana instance

### Step 1: Build the Docker Image

On your build machine:

```bash
make build-image
```

Then push to your container registry, or copy the image to your server:

```bash
# Option A: Push to registry
docker tag mcp-grafana:latest your-registry.com/mcp-grafana:latest
docker push your-registry.com/mcp-grafana:latest

# Option B: Save and transfer
docker save mcp-grafana:latest | gzip > mcp-grafana.tar.gz
scp mcp-grafana.tar.gz user@server:/tmp/
# On server: docker load < /tmp/mcp-grafana.tar.gz
```

### Step 2: Create Token File (Recommended)

Store your Grafana service account token securely:

```bash
sudo mkdir -p /etc/mcp-grafana
echo "your-service-account-token" | sudo tee /etc/mcp-grafana/token
sudo chmod 600 /etc/mcp-grafana/token
```

### Step 3: Deploy

Use the provided deployment script:

```bash
./deploy_mcp_server.sh
```

Or run manually:

```bash
docker run -d \
  --name mcp-grafana-server \
  --restart=always \
  --network host \
  -e GRAFANA_URL=https://your-grafana-instance.com \
  -e GRAFANA_SERVICE_ACCOUNT_TOKEN="$(cat /etc/mcp-grafana/token)" \
  mcp-grafana:latest \
  --transport sse \
  --address 0.0.0.0:8000
```

### Step 4: Verify

```bash
# Check health endpoint
curl http://localhost:8000/healthz

# View logs
docker logs -f mcp-grafana-server
```

---

## Configuration Reference

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GRAFANA_URL` | Grafana instance URL | `http://localhost:3000` |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | Service account token | - |
| `GRAFANA_API_KEY` | API key (deprecated) | - |
| `GRAFANA_USERNAME` | Basic auth username | - |
| `GRAFANA_PASSWORD` | Basic auth password | - |
| `GRAFANA_ORG_ID` | Organization ID | - |

### CLI Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--transport` | Transport type: `stdio`, `sse`, `streamable-http` | `stdio` |
| `--address` | Listen address for SSE/HTTP | `localhost:8000` |
| `--debug` | Enable debug logging | `false` |
| `--tls-skip-verify` | Skip TLS verification | `false` |
| `--disable-postgres` | Disable PostgreSQL tools | `false` |
| `--disable-write` | Disable all write operations | `false` |

See `./mcp-grafana --help` for the full list.

---

## Docker Restart Behavior

The `--restart=always` flag ensures the container:
- Starts automatically when Docker daemon starts (e.g., after server reboot)
- Restarts automatically if the container crashes
- Does NOT restart if manually stopped with `docker stop`

To update the container:

```bash
docker stop mcp-grafana-server
docker rm mcp-grafana-server
# Pull/load new image
./deploy_mcp_server.sh
```

---

## Connecting Clients

### Claude Code CLI

Add the MCP server using the `claude mcp add` command:

```bash
claude mcp add grafana --transport sse --url http://your-server:8000/sse
```

To verify it was added:

```bash
claude mcp list
```

To remove:

```bash
claude mcp remove grafana
```

### OpenAI Codex CLI

Add to your Codex configuration file (`~/.codex/config.json` or project-level `.codex/config.json`):

```json
{
  "mcpServers": {
    "grafana": {
      "type": "sse",
      "url": "http://your-server:8000/sse"
    }
  }
}
```

Or use the CLI:

```bash
codex mcp add grafana --url http://your-server:8000/sse
```

### Claude Desktop

Add to `~/.config/Claude/claude_desktop_config.json` (Linux) or `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS):

```json
{
  "mcpServers": {
    "grafana": {
      "url": "http://your-server:8000/sse"
    }
  }
}
```

### Health Check

```bash
curl http://your-server:8000/healthz
# Returns: ok
```
