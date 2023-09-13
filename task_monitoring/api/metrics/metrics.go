package metrics

import (
  "github.com/prometheus/client_golang/prometheus"
)

var (
  requestsTotal = prometheus.NewCounter(
      prometheus.CounterOpts{
          Name: "myapp_requests_total",
          Help: "Total number of requests to my app",
      },
  )
)

func init() {
  prometheus.MustRegister(requestsTotal)
}