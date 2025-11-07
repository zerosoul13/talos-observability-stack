# Node.js Express App - Observability Demo

An Express.js application demonstrating Prometheus metrics and structured logging integration.

## Features

- **Prometheus Metrics**: HTTP requests, duration, active requests, business operations
- **Default Metrics**: CPU, memory, event loop lag (via prom-client)
- **Structured JSON Logging**: Machine-readable logs for Loki
- **Health Checks**: Kubernetes liveness and readiness probes
- **Automatic Discovery**: Prometheus scraping via annotations

## Quick Start

### Build and Deploy

```bash
# Build Docker image
docker build -t nodejs-app:latest .

# Load into kind cluster
kind load docker-image nodejs-app:latest --name talos-dev

# Deploy to Kubernetes
kubectl apply -f deployment.yaml

# Wait for pods
kubectl rollout status deployment/nodejs-app

# Test the app
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
    curl -s http://nodejs-app.default.svc.cluster.local:8080/
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Health check |
| `/metrics` | GET | Prometheus metrics (includes Node.js default metrics) |
| `/api/data` | GET | Sample business logic |
| `/api/logs` | POST | Trigger log levels |

## API Examples

### Health Check

```bash
curl http://nodejs-app.local.dev/
```

### Get Data

```bash
curl http://nodejs-app.local.dev/api/data
```

### Trigger Logs

```bash
curl -X POST http://nodejs-app.local.dev/api/logs \
  -H "Content-Type: application/json" \
  -d '{"level":"error","message":"test_error","fields":{"code":"ERR001"}}'
```

### View Metrics

```bash
curl http://nodejs-app.local.dev/metrics
```

Example metrics output:
```
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/api/data",status="200"} 42

# HELP nodejs_heap_size_total_bytes Process heap size from Node.js in bytes.
# TYPE nodejs_heap_size_total_bytes gauge
nodejs_heap_size_total_bytes 12345678

# HELP nodejs_eventloop_lag_seconds Lag of event loop in seconds.
# TYPE nodejs_eventloop_lag_seconds gauge
nodejs_eventloop_lag_seconds 0.001
```

## Local Development

```bash
# Install dependencies
npm install

# Run locally
npm start

# Run with auto-reload (dev mode)
npm run dev

# Test
curl http://localhost:8080/
curl http://localhost:8080/metrics
```

## Monitoring

**View Logs:**
```bash
kubectl logs -f -l app=nodejs-app
```

**Port Forward:**
```bash
kubectl port-forward svc/nodejs-app 8080:8080
```

**Generate Load:**
```bash
while true; do curl -s http://nodejs-app.local.dev/api/data | jq .; sleep 1; done
```

## Configuration

- **Port**: 8080
- **Node.js Version**: 18
- **Replicas**: 2
- **Resources**: 100m CPU, 128Mi memory (request), 200m CPU, 256Mi memory (limit)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| PORT | 8080 | HTTP server port |
| NODE_ENV | production | Node environment |
| SERVICE_NAME | nodejs-app | Service name |

## Observability

The application automatically exposes metrics and logs that are collected by:
- **Grafana Alloy**: Scrapes metrics and collects logs
- **Prometheus**: Stores and queries metrics
- **Loki**: Stores and queries logs
- **Grafana**: Visualizes both metrics and logs

### Default Metrics

The application includes Node.js-specific metrics via `prom-client`:
- Memory usage (heap, RSS)
- CPU usage
- Event loop lag
- Garbage collection stats
- Active handles and requests

## Troubleshooting

**Logs not appearing:**
- Ensure logs are JSON formatted: `kubectl logs nodejs-app-xxx | head -1 | jq .`
- Check Alloy is running: `kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy`

**Metrics not in Prometheus:**
- Verify annotations: `kubectl get pod nodejs-app-xxx -o yaml | grep prometheus`
- Test metrics endpoint: `kubectl port-forward svc/nodejs-app 8080:8080 && curl localhost:8080/metrics`

**Pod crashes:**
- Check resources: `kubectl describe pod nodejs-app-xxx`
- View logs: `kubectl logs nodejs-app-xxx`
