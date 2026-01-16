package metrics

import (
	"io"
	"net/http"
	"time"
)

// MetricsRoundTripper wraps an http.RoundTripper to collect Prometheus metrics
// for all HTTP requests made through it.
type MetricsRoundTripper struct {
	underlying http.RoundTripper
	direction  string
}

// NewMetricsRoundTripper creates a new MetricsRoundTripper that wraps the given transport.
// The direction parameter should be either DirectionInbound or DirectionOutbound.
func NewMetricsRoundTripper(rt http.RoundTripper, direction string) *MetricsRoundTripper {
	if rt == nil {
		rt = http.DefaultTransport
	}
	return &MetricsRoundTripper{
		underlying: rt,
		direction:  direction,
	}
}

// RoundTrip implements http.RoundTripper, collecting metrics for each request.
func (t *MetricsRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	start := time.Now()

	IncrementActiveConnections(t.direction)
	defer DecrementActiveConnections(t.direction)

	// Get request size
	var requestSize int64
	if req.ContentLength > 0 {
		requestSize = req.ContentLength
	} else if req.Body != nil {
		// Try to get size from GetBody if available
		if req.GetBody != nil {
			if body, err := req.GetBody(); err == nil {
				if n, err := io.Copy(io.Discard, body); err == nil {
					requestSize = n
				}
				body.Close()
			}
		}
	}

	// Make the actual request
	resp, err := t.underlying.RoundTrip(req)

	duration := time.Since(start)
	host := req.URL.Host

	if err != nil {
		// Record failed request with status 0
		RecordHTTPRequest(t.direction, req.Method, host, 0, duration, requestSize, 0)
		return nil, err
	}

	// Get response size
	var responseSize int64
	if resp.ContentLength > 0 {
		responseSize = resp.ContentLength
	}

	// Record successful request
	RecordHTTPRequest(t.direction, req.Method, host, resp.StatusCode, duration, requestSize, responseSize)

	return resp, nil
}

// WrapTransport wraps a transport with metrics collection for outbound requests.
// This is a convenience function for wrapping the Grafana client transport.
func WrapTransport(rt http.RoundTripper) http.RoundTripper {
	return NewMetricsRoundTripper(rt, DirectionOutbound)
}
