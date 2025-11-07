# Python Flask App - Observability Demo

A Flask application demonstrating Prometheus metrics and structured logging integration.

## Features

- **Prometheus Metrics**: HTTP requests, duration, active requests, business operations
- **Structured JSON Logging**: Machine-readable logs for Loki
- **Health Checks**: Kubernetes liveness and readiness probes
- **Automatic Discovery**: Prometheus scraping via annotations

## Quick Start

### Build and Deploy

```bash
# Build Docker image
docker build -t python-app:latest .

# Load into kind cluster
kind load docker-image python-app:latest --name talos-dev

# Deploy to Kubernetes
kubectl apply -f deployment.yaml

# Wait for pods
kubectl rollout status deployment/python-app

# Test the app
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
    curl -s http://python-app.default.svc.cluster.local:8080/
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Health check |
| `/metrics` | GET | Prometheus metrics |
| `/api/data` | GET | Sample business logic |
| `/api/logs` | POST | Trigger log levels |

## API Examples

### Health Check

```bash
curl http://python-app.local.dev/
```

### Get Data

```bash
curl http://python-app.local.dev/api/data
```

### Trigger Logs

```bash
curl -X POST http://python-app.local.dev/api/logs \
  -H "Content-Type: application/json" \
  -d '{"level":"error","message":"test_error","fields":{"code":"ERR001"}}'
```

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run locally
python app.py

# Test
curl http://localhost:8080/
curl http://localhost:8080/metrics
```

## Monitoring

**View Logs:**
```bash
kubectl logs -f -l app=python-app
```

**Port Forward:**
```bash
kubectl port-forward svc/python-app 8080:8080
```

## Configuration

- **Port**: 8080
- **Replicas**: 2
- **Resources**: 100m CPU, 128Mi memory (request), 200m CPU, 256Mi memory (limit)
- **Python Version**: 3.11

## Observability

The application automatically exposes metrics and logs that are collected by:
- **Grafana Alloy**: Scrapes metrics and collects logs
- **Prometheus**: Stores and queries metrics
- **Loki**: Stores and queries logs
- **Grafana**: Visualizes both metrics and logs
