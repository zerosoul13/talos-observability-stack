package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Prometheus metrics
var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "path", "status"},
	)

	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)

	activeConnections = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "active_connections",
			Help: "Number of active connections",
		},
	)

	businessOperationsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "business_operations_total",
			Help: "Total number of business operations",
		},
		[]string{"operation", "status"},
	)

	dataProcessingDuration = prometheus.NewHistogram(
		prometheus.HistogramOpts{
			Name:    "data_processing_duration_seconds",
			Help:    "Duration of data processing operations",
			Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
		},
	)
)

var activeConns int64

func init() {
	// Register all Prometheus metrics
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
	prometheus.MustRegister(activeConnections)
	prometheus.MustRegister(businessOperationsTotal)
	prometheus.MustRegister(dataProcessingDuration)
}

// Logger provides structured JSON logging
type Logger struct{}

func (l *Logger) Info(message string, fields map[string]interface{}) {
	l.log("INFO", message, fields)
}

func (l *Logger) Error(message string, fields map[string]interface{}) {
	l.log("ERROR", message, fields)
}

func (l *Logger) Warn(message string, fields map[string]interface{}) {
	l.log("WARN", message, fields)
}

func (l *Logger) Debug(message string, fields map[string]interface{}) {
	l.log("DEBUG", message, fields)
}

func (l *Logger) log(level, message string, fields map[string]interface{}) {
	logEntry := map[string]interface{}{
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"level":     level,
		"message":   message,
		"service":   "sample-app",
	}

	for k, v := range fields {
		logEntry[k] = v
	}

	jsonData, _ := json.Marshal(logEntry)
	fmt.Println(string(jsonData))
}

var logger = &Logger{}

// Middleware for metrics and logging
func metricsMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Increment active connections
		atomic.AddInt64(&activeConns, 1)
		activeConnections.Set(float64(atomic.LoadInt64(&activeConns)))

		// Create response wrapper to capture status code
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		// Log request
		logger.Info("incoming_request", map[string]interface{}{
			"method":     r.Method,
			"path":       r.URL.Path,
			"remote_addr": r.RemoteAddr,
		})

		// Call next handler
		next.ServeHTTP(rw, r)

		// Calculate duration
		duration := time.Since(start).Seconds()

		// Record metrics
		httpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, fmt.Sprintf("%d", rw.statusCode)).Inc()
		httpRequestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)

		// Log response
		logger.Info("request_completed", map[string]interface{}{
			"method":       r.Method,
			"path":         r.URL.Path,
			"status":       rw.statusCode,
			"duration_ms":  duration * 1000,
		})

		// Decrement active connections
		atomic.AddInt64(&activeConns, -1)
		activeConnections.Set(float64(atomic.LoadInt64(&activeConns)))
	}
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// Handlers

// healthHandler returns health status
func healthHandler(w http.ResponseWriter, r *http.Request) {
	response := map[string]interface{}{
		"status":  "healthy",
		"service": "sample-app",
		"version": "1.0.0",
		"time":    time.Now().UTC().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// dataHandler simulates business logic with metrics
func dataHandler(w http.ResponseWriter, r *http.Request) {
	// Simulate data processing
	start := time.Now()

	// Random processing time
	processingTime := time.Duration(rand.Intn(100)+50) * time.Millisecond
	time.Sleep(processingTime)

	// Record business operation
	success := rand.Float32() > 0.1 // 90% success rate
	if success {
		businessOperationsTotal.WithLabelValues("data_fetch", "success").Inc()
	} else {
		businessOperationsTotal.WithLabelValues("data_fetch", "failure").Inc()
		logger.Error("data_fetch_failed", map[string]interface{}{
			"reason": "simulated_error",
		})
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "data processing failed",
		})
		return
	}

	dataProcessingDuration.Observe(time.Since(start).Seconds())

	// Generate sample data
	data := map[string]interface{}{
		"id":         rand.Intn(10000),
		"timestamp":  time.Now().UTC().Format(time.RFC3339),
		"value":      rand.Float64() * 100,
		"status":     "processed",
		"processing_time_ms": processingTime.Milliseconds(),
	}

	logger.Info("data_processed", map[string]interface{}{
		"record_id":    data["id"],
		"processing_ms": processingTime.Milliseconds(),
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

// logsHandler triggers different log levels
func logsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Level   string                 `json:"level"`
		Message string                 `json:"message"`
		Fields  map[string]interface{} `json:"fields"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Error("invalid_request", map[string]interface{}{
			"error": err.Error(),
		})
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "invalid request body",
		})
		return
	}

	// Trigger log based on level
	switch req.Level {
	case "info":
		logger.Info(req.Message, req.Fields)
	case "error":
		logger.Error(req.Message, req.Fields)
		businessOperationsTotal.WithLabelValues("log_trigger", "error").Inc()
	case "warn":
		logger.Warn(req.Message, req.Fields)
		businessOperationsTotal.WithLabelValues("log_trigger", "warn").Inc()
	case "debug":
		logger.Debug(req.Message, req.Fields)
	default:
		logger.Info(req.Message, req.Fields)
	}

	businessOperationsTotal.WithLabelValues("log_trigger", "success").Inc()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "logged",
		"level":  req.Level,
	})
}

func main() {
	// Seed random number generator
	rand.Seed(time.Now().UnixNano())

	logger.Info("starting_application", map[string]interface{}{
		"version": "1.0.0",
		"port":    8080,
	})

	// Setup HTTP server
	mux := http.NewServeMux()

	// Register handlers
	mux.HandleFunc("/", metricsMiddleware(healthHandler))
	mux.Handle("/metrics", promhttp.Handler()) // Prometheus metrics endpoint
	mux.HandleFunc("/api/data", metricsMiddleware(dataHandler))
	mux.HandleFunc("/api/logs", metricsMiddleware(logsHandler))

	// HTTP server configuration
	server := &http.Server{
		Addr:         ":8080",
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in goroutine
	go func() {
		logger.Info("server_listening", map[string]interface{}{
			"port": 8080,
		})
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server_error", map[string]interface{}{
				"error": err.Error(),
			})
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("shutting_down_server", map[string]interface{}{})

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		logger.Error("server_shutdown_error", map[string]interface{}{
			"error": err.Error(),
		})
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	logger.Info("server_stopped", map[string]interface{}{})
}
