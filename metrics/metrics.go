// Package metrics provides Prometheus metrics collection for the MCP Grafana server.
// It tracks HTTP request/response metrics for both client-to-MCP and MCP-to-Grafana traffic.
package metrics

import (
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

const (
	// DirectionInbound represents traffic from clients to the MCP server
	DirectionInbound = "inbound"
	// DirectionOutbound represents traffic from the MCP server to Grafana/backends
	DirectionOutbound = "outbound"
)

var (
	// httpRequestsTotal counts the total number of HTTP requests
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Namespace: "mcp_grafana",
			Name:      "http_requests_total",
			Help:      "Total number of HTTP requests",
		},
		[]string{"direction", "method", "host", "status_code"},
	)

	// httpRequestDuration tracks the duration of HTTP requests
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Namespace: "mcp_grafana",
			Name:      "http_request_duration_seconds",
			Help:      "HTTP request duration in seconds",
			Buckets:   prometheus.DefBuckets,
		},
		[]string{"direction", "method", "host"},
	)

	// httpRequestSize tracks the size of HTTP request bodies
	httpRequestSize = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Namespace: "mcp_grafana",
			Name:      "http_request_size_bytes",
			Help:      "HTTP request body size in bytes",
			Buckets:   prometheus.ExponentialBuckets(100, 10, 8), // 100B to 1GB
		},
		[]string{"direction", "method", "host"},
	)

	// httpResponseSize tracks the size of HTTP response bodies
	httpResponseSize = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Namespace: "mcp_grafana",
			Name:      "http_response_size_bytes",
			Help:      "HTTP response body size in bytes",
			Buckets:   prometheus.ExponentialBuckets(100, 10, 8), // 100B to 1GB
		},
		[]string{"direction", "method", "host"},
	)

	// httpActiveConnections tracks the number of active HTTP connections
	httpActiveConnections = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: "mcp_grafana",
			Name:      "http_active_connections",
			Help:      "Number of active HTTP connections",
		},
		[]string{"direction"},
	)

	// toolCallsTotal counts the total number of MCP tool calls
	toolCallsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Namespace: "mcp_grafana",
			Name:      "tool_calls_total",
			Help:      "Total number of MCP tool calls",
		},
		[]string{"tool", "status"},
	)

	// toolCallDuration tracks the duration of MCP tool calls
	toolCallDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Namespace: "mcp_grafana",
			Name:      "tool_call_duration_seconds",
			Help:      "MCP tool call duration in seconds",
			Buckets:   prometheus.DefBuckets,
		},
		[]string{"tool"},
	)
)

// RecordHTTPRequest records metrics for an HTTP request
func RecordHTTPRequest(direction, method, host string, statusCode int, duration time.Duration, requestSize, responseSize int64) {
	statusStr := strconv.Itoa(statusCode)

	httpRequestsTotal.WithLabelValues(direction, method, host, statusStr).Inc()
	httpRequestDuration.WithLabelValues(direction, method, host).Observe(duration.Seconds())

	if requestSize > 0 {
		httpRequestSize.WithLabelValues(direction, method, host).Observe(float64(requestSize))
	}
	if responseSize > 0 {
		httpResponseSize.WithLabelValues(direction, method, host).Observe(float64(responseSize))
	}
}

// IncrementActiveConnections increments the active connection count
func IncrementActiveConnections(direction string) {
	httpActiveConnections.WithLabelValues(direction).Inc()
}

// DecrementActiveConnections decrements the active connection count
func DecrementActiveConnections(direction string) {
	httpActiveConnections.WithLabelValues(direction).Dec()
}

// RecordToolCall records metrics for an MCP tool call
func RecordToolCall(tool string, success bool, duration time.Duration) {
	status := "success"
	if !success {
		status = "error"
	}
	toolCallsTotal.WithLabelValues(tool, status).Inc()
	toolCallDuration.WithLabelValues(tool).Observe(duration.Seconds())
}

