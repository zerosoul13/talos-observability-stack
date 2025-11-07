#!/usr/bin/env node

/**
 * Node.js Express Application with Prometheus Metrics
 * Demonstrates observability integration with structured logging and metrics
 */

const express = require('express');
const promClient = require('prom-client');

const app = express();
const PORT = process.env.PORT || 8080;

// Configure JSON body parser
app.use(express.json());

// Create a Registry for Prometheus metrics
const register = new promClient.Registry();

// Add default metrics (CPU, memory, etc.)
promClient.collectDefaultMetrics({ register });

// Custom Prometheus metrics
const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'path', 'status'],
  registers: [register]
});

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'path'],
  registers: [register]
});

const activeRequests = new promClient.Gauge({
  name: 'active_requests',
  help: 'Number of active requests',
  registers: [register]
});

const businessOperationsTotal = new promClient.Counter({
  name: 'business_operations_total',
  help: 'Total business operations',
  labelNames: ['operation', 'status'],
  registers: [register]
});

// Structured JSON logger
class Logger {
  log(level, message, fields = {}) {
    const logEntry = {
      timestamp: new Date().toISOString(),
      level: level.toUpperCase(),
      message,
      service: 'nodejs-app',
      ...fields
    };
    console.log(JSON.stringify(logEntry));
  }

  info(message, fields) {
    this.log('info', message, fields);
  }

  error(message, fields) {
    this.log('error', message, fields);
  }

  warn(message, fields) {
    this.log('warn', message, fields);
  }

  debug(message, fields) {
    this.log('debug', message, fields);
  }
}

const logger = new Logger();

// Middleware for metrics and logging
app.use((req, res, next) => {
  const start = Date.now();

  // Increment active requests
  activeRequests.inc();

  // Log incoming request
  logger.info('incoming_request', {
    method: req.method,
    path: req.path,
    remote_addr: req.ip
  });

  // Override res.end to capture metrics after response
  const originalEnd = res.end;
  res.end = function(...args) {
    // Calculate duration
    const duration = (Date.now() - start) / 1000;

    // Record metrics
    httpRequestsTotal.labels(req.method, req.path, res.statusCode).inc();
    httpRequestDuration.labels(req.method, req.path).observe(duration);
    activeRequests.dec();

    // Log response
    logger.info('request_completed', {
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration_ms: duration * 1000
    });

    // Call original end
    originalEnd.apply(res, args);
  };

  next();
});

// Routes

// Health check endpoint
app.get('/', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'nodejs-app',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Data endpoint with business logic
app.get('/api/data', (req, res) => {
  // Simulate processing time
  const processingTime = Math.random() * 100 + 50; // 50-150ms

  setTimeout(() => {
    // Simulate success/failure (90% success rate)
    const success = Math.random() > 0.1;

    if (!success) {
      businessOperationsTotal.labels('data_fetch', 'failure').inc();
      logger.error('data_fetch_failed', {
        reason: 'simulated_error'
      });
      return res.status(500).json({ error: 'data processing failed' });
    }

    businessOperationsTotal.labels('data_fetch', 'success').inc();

    // Generate sample data
    const data = {
      id: Math.floor(Math.random() * 10000),
      timestamp: new Date().toISOString(),
      value: Math.random() * 100,
      status: 'processed',
      processing_time_ms: processingTime
    };

    logger.info('data_processed', {
      record_id: data.id,
      processing_ms: processingTime
    });

    res.json(data);
  }, processingTime);
});

// Logs endpoint to trigger different log levels
app.post('/api/logs', (req, res) => {
  const { level = 'info', message = 'test_message', fields = {} } = req.body;

  // Log based on level
  switch (level.toLowerCase()) {
    case 'info':
      logger.info(message, fields);
      break;
    case 'error':
      logger.error(message, fields);
      businessOperationsTotal.labels('log_trigger', 'error').inc();
      break;
    case 'warn':
    case 'warning':
      logger.warn(message, fields);
      businessOperationsTotal.labels('log_trigger', 'warning').inc();
      break;
    case 'debug':
      logger.debug(message, fields);
      break;
    default:
      logger.info(message, fields);
  }

  businessOperationsTotal.labels('log_trigger', 'success').inc();

  res.json({
    status: 'logged',
    level: level
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'not found' });
});

// Error handler
app.use((err, req, res, next) => {
  logger.error('internal_server_error', {
    error: err.message,
    stack: err.stack
  });
  res.status(500).json({ error: 'internal server error' });
});

// Start server
const server = app.listen(PORT, '0.0.0.0', () => {
  logger.info('starting_application', {
    version: '1.0.0',
    port: PORT
  });
  logger.info('server_listening', {
    port: PORT,
    address: '0.0.0.0'
  });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('shutting_down_server', {});

  server.close(() => {
    logger.info('server_stopped', {});
    process.exit(0);
  });

  // Force close after 30 seconds
  setTimeout(() => {
    logger.error('server_shutdown_timeout', {});
    process.exit(1);
  }, 30000);
});

process.on('SIGINT', () => {
  logger.info('shutting_down_server', {});

  server.close(() => {
    logger.info('server_stopped', {});
    process.exit(0);
  });
});
