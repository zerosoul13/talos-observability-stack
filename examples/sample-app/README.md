# Sample App - Go Observability Demo

A comprehensive Go application demonstrating observability platform integration with Prometheus metrics, structured logging, and Kubernetes service discovery.

## Features

### Prometheus Metrics
- **HTTP Metrics**: Request counters, duration histograms, active connections
- **Business Metrics**: Operation counters, processing duration
- **Automatic Labels**: Method, path, status code
- **Standard Endpoint**: `/metrics` for Prometheus scraping

### Structured Logging
- **JSON Format**: Machine-readable logs for Loki
- **Log Levels**: INFO, WARN, ERROR, DEBUG
- **Contextual Fields**: Timestamps, service info, custom fields
- **Request Tracing**: Log all incoming requests and responses

### Health Checks
- **Liveness Probe**: Application health status
- **Readiness Probe**: Ready to accept traffic
- **Kubernetes Integration**: Automatic pod management

## Architecture

```
┌─────────────────┐
│   Sample App    │
│   (Port 8080)   │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼──┐  ┌──▼────┐
│Metrics│  │ Logs  │
│ /metrics│  │JSON  │
└───┬──┘  └──┬────┘
    │         │
┌───▼──┐  ┌──▼────┐
│Alloy │  │ Alloy │
└───┬──┘  └──┬────┘
    │         │
┌───▼──┐  ┌──▼────┐
│Prom  │  │ Loki  │
└──────┘  └───────┘
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Health check - returns service status |
| `/metrics` | GET | Prometheus metrics endpoint |
| `/api/data` | GET | Sample business logic with metrics |
| `/api/logs` | POST | Trigger different log levels |

## Quick Start

### 1. Build the Application

```bash
./build.sh
```

This will:
- Build the Docker image
- Tag it as `sample-app:latest`
- Load it into your kind/Talos cluster

### 2. Deploy to Kubernetes

```bash
./deploy.sh
```

This will:
- Apply deployment, service, and ingress manifests
- Wait for pods to be ready
- Show deployment status and logs

### 3. Test the Application

```bash
./test.sh
```

This will:
- Send requests to all endpoints
- Verify metrics are exposed
- Check logs are being generated
- Validate Prometheus and Loki integration

## Manual Usage

### Build Docker Image

```bash
docker build -t sample-app:latest .
```

### Load into kind Cluster

```bash
kind load docker-image sample-app:latest --name talos-dev
```

### Deploy to Kubernetes

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

### Access the Application

**Via ClusterIP (from within cluster):**
```bash
kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
    curl -s http://sample-app.default.svc.cluster.local:8080/
```

**Via Port Forward:**
```bash
kubectl port-forward svc/sample-app 8080:8080
curl http://localhost:8080/
```

**Via Ingress (requires /etc/hosts entry):**
```bash
# Add to /etc/hosts: <traefik-ip> app.local.dev
curl http://app.local.dev/
```

## API Examples

### Health Check

```bash
curl http://app.local.dev/
```

Response:
```json
{
  "status": "healthy",
  "service": "sample-app",
  "version": "1.0.0",
  "time": "2025-11-01T12:00:00Z"
}
```

### Get Data (Business Logic)

```bash
curl http://app.local.dev/api/data
```

Response:
```json
{
  "id": 1234,
  "timestamp": "2025-11-01T12:00:00Z",
  "value": 42.5,
  "status": "processed",
  "processing_time_ms": 75
}
```

### Trigger Logs

```bash
curl -X POST http://app.local.dev/api/logs \
  -H "Content-Type: application/json" \
  -d '{
    "level": "error",
    "message": "test_error_message",
    "fields": {
      "error_code": "TEST_001",
      "user_id": "12345"
    }
  }'
```

Response:
```json
{
  "status": "logged",
  "level": "error"
}
```

### View Metrics

```bash
curl http://app.local.dev/metrics
```

Sample output:
```
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/api/data",status="200"} 42

# HELP http_request_duration_seconds HTTP request duration in seconds
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",path="/api/data",le="0.005"} 10
http_request_duration_seconds_bucket{method="GET",path="/api/data",le="0.01"} 25
```

## Observability Integration

### Prometheus Scraping

The deployment includes annotations for automatic Prometheus discovery:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

Grafana Alloy automatically discovers and scrapes this service.

### Metrics Available

**HTTP Metrics:**
- `http_requests_total` - Total HTTP requests by method, path, status
- `http_request_duration_seconds` - Request duration histogram
- `active_connections` - Current active connections

**Business Metrics:**
- `business_operations_total` - Business operations by type and status
- `data_processing_duration_seconds` - Data processing time histogram

### Loki Log Collection

Logs are automatically collected by Grafana Alloy and sent to Loki.

**Log Format:**
```json
{
  "timestamp": "2025-11-01T12:00:00Z",
  "level": "INFO",
  "message": "request_completed",
  "service": "sample-app",
  "method": "GET",
  "path": "/api/data",
  "status": 200,
  "duration_ms": 75.5
}
```

**Query in Grafana:**
```logql
{app="sample-app"} |= "request_completed"
```

## Monitoring and Troubleshooting

### View Logs

```bash
# Tail logs from all pods
kubectl logs -f -l app=sample-app

# Tail logs from specific pod
kubectl logs -f sample-app-<pod-id>

# View last 100 lines
kubectl logs -l app=sample-app --tail=100
```

### Check Metrics

```bash
# Port forward and view metrics
kubectl port-forward svc/sample-app 8080:8080
curl http://localhost:8080/metrics
```

### Debug Deployment

```bash
# Check pod status
kubectl get pods -l app=sample-app

# Describe pod
kubectl describe pod sample-app-<pod-id>

# Check deployment
kubectl describe deployment sample-app

# Check service
kubectl describe svc sample-app
```

### Generate Load

```bash
# Continuous requests
while true; do
  curl -s http://app.local.dev/api/data | jq .
  sleep 1
done

# Parallel requests
for i in {1..100}; do
  curl -s http://app.local.dev/api/data &
done
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| SERVICE_NAME | sample-app | Service name for logging |
| SERVICE_VERSION | 1.0.0 | Service version |
| ENVIRONMENT | development | Environment name |

### Resource Limits

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

### Scaling

```bash
# Scale to 5 replicas
kubectl scale deployment sample-app --replicas=5

# Autoscaling (requires metrics-server)
kubectl autoscale deployment sample-app --cpu-percent=70 --min=2 --max=10
```

## Development

### Local Development

```bash
# Run locally
go run main.go

# Build binary
go build -o sample-app main.go

# Run binary
./sample-app
```

### Testing Locally

```bash
# Health check
curl http://localhost:8080/

# Metrics
curl http://localhost:8080/metrics

# Data endpoint
curl http://localhost:8080/api/data

# Logs endpoint
curl -X POST http://localhost:8080/api/logs \
  -H "Content-Type: application/json" \
  -d '{"level":"info","message":"test"}'
```

### Building for Production

```bash
# Build optimized image
docker build --no-cache -t sample-app:v1.0.0 .

# Tag for registry
docker tag sample-app:v1.0.0 registry.example.com/sample-app:v1.0.0

# Push to registry
docker push registry.example.com/sample-app:v1.0.0
```

## Security

- **Non-root user**: Application runs as user 1000
- **Read-only filesystem**: Root filesystem is read-only
- **No privilege escalation**: Security context prevents escalation
- **Dropped capabilities**: All Linux capabilities dropped
- **Resource limits**: CPU and memory limits enforced

## Troubleshooting

### Pods not starting

```bash
# Check pod events
kubectl describe pod sample-app-<pod-id>

# Check logs
kubectl logs sample-app-<pod-id>

# Verify image is available
docker images | grep sample-app
```

### Metrics not appearing in Prometheus

1. Check pod annotations:
```bash
kubectl get pod sample-app-<pod-id> -o yaml | grep prometheus
```

2. Verify metrics endpoint:
```bash
kubectl port-forward svc/sample-app 8080:8080
curl http://localhost:8080/metrics
```

3. Check Alloy is scraping:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy
```

### Logs not in Loki

1. Verify logs are JSON formatted:
```bash
kubectl logs sample-app-<pod-id> | head -1 | jq .
```

2. Check Alloy is collecting logs:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy | grep sample-app
```

## License

MIT
