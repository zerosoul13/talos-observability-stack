# Observability Stack Documentation

## Overview

The Talos Local Observability Platform includes a complete observability stack for monitoring and logging Kubernetes applications:

- **Prometheus**: Time-series metrics storage
- **Loki**: Log aggregation and querying
- **Grafana**: Visualization and dashboards
- **Grafana Alloy**: Universal telemetry collection agent

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Pods                         │
│  (with prometheus.io/* annotations)                         │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ metrics + logs
                 ▼
┌─────────────────────────────────────────────────────────────┐
│                    Grafana Alloy                            │
│  • Auto-discovers pods via annotations                      │
│  • Scrapes metrics from /metrics endpoints                  │
│  • Collects logs from containers                            │
└────────────┬────────────────────────────────────┬───────────┘
             │                                    │
             │ remote_write                       │ push
             ▼                                    ▼
    ┌────────────────┐                  ┌────────────────┐
    │   Prometheus   │                  │      Loki      │
    │  (15d retention)                  │  (7d retention)│
    └────────┬───────┘                  └────────┬───────┘
             │                                    │
             │ PromQL queries                     │ LogQL queries
             └────────────────┬───────────────────┘
                              ▼
                     ┌────────────────┐
                     │    Grafana     │
                     │  • Dashboards  │
                     │  • Explore     │
                     │  • Alerting    │
                     └────────────────┘
```

## Quick Start

### 1. Deploy the Observability Stack

```bash
# Ensure Talos cluster is running
make status

# Deploy complete observability stack
make deploy-observability
```

This will:
- Create `monitoring` namespace
- Deploy Prometheus with 10GB storage
- Deploy Loki with 5GB storage
- Deploy Grafana with pre-configured datasources and dashboards
- Install Grafana Alloy via Helm

### 2. Access Grafana

```bash
# Port-forward to Grafana
make grafana-dashboard

# Open in browser: http://localhost:3000
# Credentials: admin / admin
```

### 3. Deploy a Test Application

```bash
# Deploy test application with metrics annotations
kubectl apply -f examples/test-app-with-metrics.yaml

# Wait for pods to be ready
kubectl get pods -n test-app -w

# Verify metrics are being collected
make grafana-dashboard
# Navigate to Explore > Prometheus > Metrics browser
```

## Components

### Prometheus

**Purpose**: Time-series metrics storage and querying

**Configuration**:
- Retention: 15 days
- Storage: 10GB PersistentVolume
- Receives metrics via remote write from Alloy
- Self-scrapes for monitoring

**Access**:
```bash
# Port-forward to Prometheus UI
make prometheus-ui

# Or manually
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open: http://localhost:9090
```

**View Logs**:
```bash
make logs-prometheus
```

### Loki

**Purpose**: Log aggregation and querying system

**Configuration**:
- Retention: 7 days
- Storage: 5GB PersistentVolume
- Single-node deployment with BoltDB + filesystem
- Receives logs from Alloy via push API

**Query Logs in Grafana**:
1. Open Grafana: `make grafana-dashboard`
2. Navigate to Explore
3. Select "Loki" datasource
4. Use LogQL to query logs

**View Logs**:
```bash
make logs-loki
```

### Grafana

**Purpose**: Visualization, dashboards, and exploration

**Configuration**:
- Anonymous access enabled (local dev)
- Default credentials: admin / admin
- Pre-configured datasources (Prometheus, Loki)
- Pre-loaded dashboards

**Pre-built Dashboards**:
1. **Kubernetes Cluster Overview**: Node CPU, memory, pod counts
2. **Pod Metrics Dashboard**: Per-pod resource usage
3. **Logs Explorer**: Query and filter logs by namespace/pod

**Access**:
```bash
make grafana-dashboard
```

### Grafana Alloy

**Purpose**: Universal telemetry collection agent

**Configuration**:
- Deployed via k8s-monitoring Helm chart
- Auto-discovers pods with Prometheus annotations
- Collects logs from all containers
- Remote writes metrics to Prometheus
- Pushes logs to Loki

**View Logs**:
```bash
make logs-alloy
```

## Annotation-Based Service Discovery

Grafana Alloy automatically discovers and scrapes applications with these annotations:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"    # Enable scraping
        prometheus.io/port: "8080"      # Port with /metrics endpoint
        prometheus.io/path: "/metrics"  # Metrics path (default: /metrics)
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        ports:
        - containerPort: 8080
```

**Supported Annotations**:
- `prometheus.io/scrape`: Set to "true" to enable scraping
- `prometheus.io/port`: Port number where metrics are exposed
- `prometheus.io/path`: Path to metrics endpoint (optional, defaults to /metrics)

## Storage and Retention

### Prometheus Storage

- **Size**: 10GB
- **Retention**: 15 days
- **Location**: `/prometheus` in pod
- **PVC**: `prometheus-pvc` in `monitoring` namespace

### Loki Storage

- **Size**: 5GB
- **Retention**: 7 days
- **Location**: `/loki` in pod
- **PVC**: `loki-pvc` in `monitoring` namespace

### Managing Storage

```bash
# View PVCs
kubectl get pvc -n monitoring

# Check storage usage
kubectl exec -n monitoring deployment/prometheus -- df -h /prometheus
kubectl exec -n monitoring deployment/loki -- df -h /loki

# Delete PVCs (WARNING: All data will be lost)
kubectl delete pvc -n monitoring prometheus-pvc loki-pvc
```

## Makefile Commands

### Deployment

```bash
make deploy-observability              # Deploy complete stack
make destroy-observability             # Remove stack (deletes data)
make destroy-observability-keep-data   # Remove stack (keeps PVCs)
```

### Access

```bash
make grafana-dashboard    # Port-forward to Grafana (localhost:3000)
make prometheus-ui        # Port-forward to Prometheus (localhost:9090)
```

### Monitoring

```bash
make monitoring-status    # Show all monitoring components
make logs-prometheus      # Stream Prometheus logs
make logs-loki           # Stream Loki logs
make logs-alloy          # Stream Grafana Alloy logs
```

## Common Operations

### Verifying Metrics Collection

1. Deploy an application with annotations:
   ```bash
   kubectl apply -f examples/test-app-with-metrics.yaml
   ```

2. Port-forward to Prometheus:
   ```bash
   make prometheus-ui
   ```

3. Check targets in Prometheus UI:
   - Open http://localhost:9090
   - Navigate to Status > Targets
   - Verify your application appears and is UP

4. Query metrics in Grafana:
   ```bash
   make grafana-dashboard
   ```
   - Navigate to Explore
   - Select Prometheus datasource
   - Try query: `up{namespace="test-app"}`

### Viewing Logs

1. Port-forward to Grafana:
   ```bash
   make grafana-dashboard
   ```

2. Navigate to Explore

3. Select Loki datasource

4. Use LogQL queries:
   ```logql
   # All logs from namespace
   {namespace="test-app"}

   # Logs from specific pod
   {namespace="test-app", pod=~"test-app-.*"}

   # Filter by log content
   {namespace="test-app"} |= "error"

   # Regex filter
   {namespace="test-app"} |~ "error|warn"
   ```

### Troubleshooting

**Problem**: Metrics not appearing in Prometheus

**Solutions**:
1. Check Alloy is discovering the pod:
   ```bash
   make logs-alloy | grep "discovered"
   ```

2. Verify annotations on your pod:
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o yaml | grep annotations -A 5
   ```

3. Check Prometheus targets:
   ```bash
   make prometheus-ui
   # Navigate to Status > Targets
   ```

4. Verify metrics endpoint is accessible:
   ```bash
   kubectl port-forward -n <namespace> <pod-name> 8080:8080
   curl http://localhost:8080/metrics
   ```

**Problem**: Logs not appearing in Loki

**Solutions**:
1. Check Loki is receiving logs:
   ```bash
   make logs-loki | grep "ingester"
   ```

2. Verify Alloy is sending logs:
   ```bash
   make logs-alloy | grep "loki"
   ```

3. Check Loki ingestion stats:
   ```bash
   kubectl port-forward -n monitoring svc/loki 3100:3100
   curl http://localhost:3100/metrics | grep loki_ingester
   ```

**Problem**: Alloy not discovering pods

**Solutions**:
1. Check RBAC permissions:
   ```bash
   kubectl get clusterrole alloy -o yaml
   kubectl get clusterrolebinding alloy -o yaml
   ```

2. Verify Alloy configuration:
   ```bash
   kubectl get configmap -n monitoring alloy-config -o yaml
   ```

3. Check Alloy logs for errors:
   ```bash
   make logs-alloy
   ```

## Resource Usage

Typical resource consumption:

| Component  | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| Prometheus | 250m        | 1000m     | 512Mi          | 2Gi          |
| Loki       | 100m        | 500m      | 256Mi          | 1Gi          |
| Grafana    | 100m        | 500m      | 128Mi          | 512Mi        |
| Alloy      | 100m        | 500m      | 128Mi          | 512Mi        |
| **Total**  | **550m**    | **2500m** | **1024Mi**     | **4Gi**      |

## Customization

### Adjusting Retention Periods

**Prometheus** (edit `prometheus-deployment.yaml`):
```yaml
args:
  - '--storage.tsdb.retention.time=30d'  # Change from 15d to 30d
```

**Loki** (edit `loki-config.yaml`):
```yaml
limits_config:
  retention_period: 336h  # 14 days (change from 168h)
```

### Adjusting Storage Sizes

**Prometheus** (edit `prometheus-pvc.yaml`):
```yaml
resources:
  requests:
    storage: 20Gi  # Change from 10Gi
```

**Loki** (edit `loki-pvc.yaml`):
```yaml
resources:
  requests:
    storage: 10Gi  # Change from 5Gi
```

After making changes, redeploy:
```bash
make destroy-observability-keep-data
make deploy-observability
```

### Adding Custom Dashboards

1. Create dashboard in Grafana UI
2. Export as JSON (Share > Export)
3. Add to `grafana-dashboards.yaml`:
   ```yaml
   data:
     my-custom-dashboard.json: |
       {
         "dashboard": { ... }
       }
   ```
4. Redeploy Grafana:
   ```bash
   kubectl apply -f infrastructure/observability/grafana-dashboards.yaml
   kubectl rollout restart deployment/grafana -n monitoring
   ```

## Security Considerations

This stack is configured for local development with the following security settings:

- **Grafana**: Anonymous access enabled (admin role)
- **Prometheus**: No authentication
- **Loki**: No authentication
- **Internal communication**: No TLS

**For production use**:
1. Enable authentication on all components
2. Use TLS for internal communication
3. Implement network policies
4. Use secrets for credentials
5. Enable RBAC restrictions

## Backup and Restore

### Backup Data

```bash
# Backup Prometheus data
kubectl cp monitoring/prometheus-<pod-id>:/prometheus ./prometheus-backup

# Backup Loki data
kubectl cp monitoring/loki-<pod-id>:/loki ./loki-backup
```

### Restore Data

```bash
# Restore Prometheus data
kubectl cp ./prometheus-backup monitoring/prometheus-<pod-id>:/prometheus

# Restore Loki data
kubectl cp ./loki-backup monitoring/loki-<pod-id>:/loki

# Restart pods
kubectl rollout restart deployment/prometheus -n monitoring
kubectl rollout restart deployment/loki -n monitoring
```

## Uninstallation

### Remove stack but keep data
```bash
make destroy-observability-keep-data
```

### Complete removal (including data)
```bash
make destroy-observability
```

### Manual cleanup
```bash
# Remove all resources
kubectl delete namespace monitoring

# Verify removal
kubectl get all -n monitoring
```

## Next Steps

1. Deploy your application with Prometheus annotations
2. Create custom Grafana dashboards
3. Set up alerting rules in Prometheus
4. Configure log aggregation pipelines in Loki
5. Explore distributed tracing (future: add Tempo)

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [Kubernetes Annotations](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/)
