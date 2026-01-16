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
4. Go 1.24+ (only if building on the server)

---

### Option A: Build and Deploy on the Server (No Registry Required)

If you don't have a container registry, you can clone and build directly on the destination server.

#### Step 1: Clone the repository

```bash
git clone https://github.com/ryan-rbw/mcp-grafana.git
cd mcp-grafana
```

#### Step 2: Build the Docker image

```bash
make build-image
```

#### Step 3: Create token file

```bash
sudo mkdir -p /etc/mcp-grafana
echo "your-service-account-token" | sudo tee /etc/mcp-grafana/token
sudo chmod 600 /etc/mcp-grafana/token
```

#### Step 4: Configure and deploy

Edit `deploy_mcp_server.sh` to set your Grafana host and IP:

```bash
GRAFANA_HOST="your-grafana.example.com"
GRAFANA_IP="10.x.x.x"  # Internal IP if DNS doesn't resolve inside Docker
```

Then deploy:

```bash
chmod +x deploy_mcp_server.sh
./deploy_mcp_server.sh
```

#### Step 5: Verify

```bash
curl http://localhost:8000/healthz
# Returns: ok
```

---

### Option B: Build Locally and Transfer Image

If you prefer to build on a separate machine and transfer the image.

#### Step 1: Build the Docker image

On your build machine:

```bash
make build-image
```

#### Step 2: Transfer to server

```bash
# Option 1: Push to registry
docker tag mcp-grafana:latest your-registry.com/mcp-grafana:latest
docker push your-registry.com/mcp-grafana:latest

# Option 2: Save and transfer (no registry required)
docker save mcp-grafana:latest | gzip > mcp-grafana.tar.gz
scp mcp-grafana.tar.gz user@server:/tmp/
# On server:
docker load < /tmp/mcp-grafana.tar.gz
```

#### Step 3: Create token file (on server)

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

The server supports two transport modes:

- **SSE** (`/sse`): For Claude Desktop, Claude Code CLI
- **Streamable HTTP** (`/mcp`): For Codex CLI and newer MCP clients

The deploy script defaults to `streamable-http`. To use SSE instead:

```bash
TRANSPORT=sse ./deploy_mcp_server.sh
```

### Claude Code CLI

Add the MCP server using the `claude mcp add` command:

```bash
# For streamable-http transport (default)
claude mcp add --transport http grafana http://your-server:8000/mcp

# For SSE transport
claude mcp add --transport sse grafana http://your-server:8000/sse
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

Codex CLI requires streamable HTTP transport (the default). Add to your Codex configuration file (`~/.codex/config.json` or project-level `.codex/config.json`):

```json
{
  "mcpServers": {
    "grafana": {
      "url": "http://your-server:8000/mcp"
    }
  }
}
```

### Claude Desktop

Claude Desktop requires SSE transport. Deploy with `TRANSPORT=sse ./deploy_mcp_server.sh`, then add to `~/.config/Claude/claude_desktop_config.json` (Linux) or `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS):

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
