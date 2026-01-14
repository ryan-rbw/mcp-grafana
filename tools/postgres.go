package tools

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/grafana/grafana-plugin-sdk-go/data"
	mcpgrafana "github.com/grafana/mcp-grafana"
	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

type QueryPostgresParams struct {
	DatasourceUID string `json:"datasourceUid" jsonschema:"required,description=The UID of the datasource to query"`
	RawSql        string `json:"rawSql" jsonschema:"required,description=The raw SQL query to execute"`
	Format        string `json:"format,omitempty" jsonschema:"default=table,description=The format of the response. Currently only 'table' is supported."`
}

func queryPostgres(ctx context.Context, args QueryPostgresParams) (*data.Frame, error) {
	c := mcpgrafana.GrafanaClientFromContext(ctx)
	if c == nil {
		return nil, fmt.Errorf("grafana client not found in context")
	}

	// We'll mimic the request structure for /api/ds/query
	requestBody := map[string]interface{}{
		"from": "now-1h", // Arbitrary default, required by API
		"to":   "now",
		"queries": []map[string]interface{}{
			{
				"refId":         "A",
				"datasource":    map[string]string{"uid": args.DatasourceUID},
				"rawSql":        args.RawSql,
				"format":        "table",
				"intervalMs":    1000,
				"maxDataPoints": 1000,
			},
		},
	}

	return executeRawQuery(ctx, requestBody)
}

// executeRawQuery helper to send JSON to /api/ds/query
func executeRawQuery(ctx context.Context, body interface{}) (*data.Frame, error) {
	c := mcpgrafana.GrafanaClientFromContext(ctx)
	_ = c // potentially unused if we use config directly, but good to have context check

	// Marshaling body
	jsonBody, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshaling request body: %w", err)
	}

	cfg := mcpgrafana.GrafanaConfigFromContext(ctx)
	url := fmt.Sprintf("%s/api/ds/query", cfg.URL)
	
	// Build request
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	
	// Auth headers 
	if cfg.AccessToken != "" && cfg.IDToken != "" {
		req.Header.Set("X-Access-Token", cfg.AccessToken)
		req.Header.Set("X-Grafana-Id", cfg.IDToken)
	} else if cfg.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
	} else if cfg.BasicAuth != nil {
		req.SetBasicAuth(cfg.BasicAuth.Username(), func() string { p, _ := cfg.BasicAuth.Password(); return p }())
	}
	if cfg.OrgID != 0 {
		req.Header.Set("X-Grafana-Org-Id", fmt.Sprintf("%d", cfg.OrgID))
	}

	// Create a client to execute
	httpClient := &http.Client{}
	
	// If we have custom TLS
	if cfg.TLSConfig != nil {
		tlsConfig, err := cfg.TLSConfig.CreateTLSConfig()
		if err != nil {
			return nil, err
		}
		httpClient.Transport = &http.Transport{
			TLSClientConfig: tlsConfig,
		}
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("executing request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("request failed with status %d", resp.StatusCode)
	}

	// Parse response
	// structure: { "results": { "A": { "frames": [...] } } }
	var resultEnvelope struct {
		Results map[string]struct {
			Frames []json.RawMessage `json:"frames"`
		} `json:"results"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&resultEnvelope); err != nil {
		return nil, fmt.Errorf("decoding response: %w", err)
	}

	framesA, ok := resultEnvelope.Results["A"]
	if !ok || len(framesA.Frames) == 0 {
		return nil, fmt.Errorf("no results found")
	}

	// We return the first frame for now
	var frame data.Frame
	if err := json.Unmarshal(framesA.Frames[0], &frame); err != nil {
		return nil, fmt.Errorf("unmarshaling frame: %w", err)
	}

	return &frame, nil
}

var QueryPostgres = mcpgrafana.MustTool(
	"query_postgres",
	"Execute a raw SQL query against a PostgreSQL or TimescaleDB datasource. Returns the result as a table.",
	queryPostgres,
	mcp.WithTitleAnnotation("Query PostgreSQL/TimescaleDB"),
)

func AddPostgresTools(mcp *server.MCPServer) {
	QueryPostgres.Register(mcp)
}
