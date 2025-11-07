# Talos Local Development Platform

A complete, production-grade local Kubernetes development environment running on Talos Linux with full observability stack.

## Overview

This platform provides a fully-featured local Kubernetes cluster with:
- **Talos Linux** - Secure, immutable Kubernetes OS running in Docker
- **Kubernetes v1.31.1** - Latest stable cluster
- **Traefik Ingress** - Production-ready HTTP/HTTPS routing with automatic TLS
- **Grafana Alloy** - Unified observability agent for metrics and logs
- **Prometheus** - Metrics storage and querying
- **Loki** - Log aggregation and querying
- **Grafana** - Unified dashboards and visualization
- **Auto-discovery** - Automatic metrics scraping via Kubernetes annotations

## Quick Start

### Prerequisites

- **Docker Desktop or Docker Engine** (20.10+)
- **kubectl** (1.28+)
- **helm** (3.12+)
- **talosctl** (see installation below)
- **make** (optional, simplifies commands)

**System Requirements:**
- Minimum: 8GB RAM, 4 CPU cores, 20GB disk
- Recommended: 16GB RAM, 8 CPU cores, 40GB disk

### Installation

```bash
# 1. Install talosctl
curl -sL https://talos.dev/install | sh

# 2. Deploy the entire platform (3-5 minutes)
make deploy-infra
make deploy-traefik
make deploy-observability

# Or deploy everything at once
make deploy

# 3. Verify deployment
make status

# 4. View service endpoints
make endpoints
```

### Add to /etc/hosts

**IMPORTANT**: Add these entries to your `/etc/hosts` file for all services to work:

```bash
# BEGIN Talos Local Dev
127.0.0.1 grafana.local.dev
127.0.0.1 prometheus.local.dev
127.0.0.1 traefik.local.dev
127.0.0.1 argocd.local.dev
127.0.0.1 app.local.dev
# END Talos Local Dev
```

On Linux/macOS:
```bash
sudo nano /etc/hosts
# Add the entries above, save and exit
```

On Windows:
```powershell
# Run as Administrator
notepad C:\Windows\System32\drivers\etc\hosts
# Add the entries above, save and exit
```

## Architecture

The platform consists of three main layers:

### 1. Infrastructure Layer (Talos + Kubernetes)
- **Talos Cluster**: 1 control plane + 2 worker nodes
- **Network**: Custom Docker bridge network with port forwarding
- **Storage**: Local-path-provisioner for persistent volumes

### 2. Ingress Layer (Traefik)
- **HTTP/HTTPS Routing**: Port 80 and 443 exposed to localhost
- **IngressRoute Support**: Traefik CRDs for advanced routing
- **Dashboard**: Web UI for monitoring routes and services
- **Automatic TLS**: Self-signed certificates for HTTPS

### 3. Observability Layer (Grafana Stack)
- **Grafana Alloy**: Collects logs and metrics from all pods
- **Prometheus**: Stores and queries time-series metrics (392+ metrics)
- **Loki**: Stores and queries logs from all namespaces
- **Grafana**: Unified visualization with pre-configured datasources

See [docs/Architecture.md](docs/Architecture.md) for detailed system design.

## Service Endpoints

After deployment, access services at:

| Service | URL | Description |
|---------|-----|-------------|
| Traefik Dashboard | https://traefik.local.dev/dashboard/ | Ingress controller dashboard |
| Grafana | https://grafana.local.dev/ | Metrics and logs visualization |
| Prometheus | https://prometheus.local.dev/ | Metrics query interface |
| Sample App | https://app.local.dev/ | Example application (when deployed) |

**Note**: Accept self-signed certificate warnings in your browser.

## Adding Your Applications

### 1. Deploy Your Application

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
  annotations:
    # Enable automatic metrics scraping
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: default
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
```

### 2. Create an IngressRoute

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: default
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`my-app.local.dev`)
      kind: Rule
      services:
        - name: my-app
          port: 80
```

### 3. View Logs and Metrics

- **Logs**: Go to Grafana → Explore → Select "Loki" → Query: `{namespace="default", pod=~"my-app.*"}`
- **Metrics**: Go to Grafana → Explore → Select "Prometheus" → Query: `up{job="default/my-app"}`

## Common Commands

```bash
# Cluster Management
make deploy-infra           # Deploy Talos cluster
make destroy-infra          # Destroy Talos cluster
make status                 # Show cluster status

# Service Management
make deploy-traefik         # Deploy Traefik ingress
make deploy-observability   # Deploy monitoring stack
make deploy                 # Deploy everything

# Monitoring
make endpoints              # List all service URLs
make logs-traefik          # View Traefik logs
make logs-alloy            # View Alloy logs
make logs-prometheus       # View Prometheus logs

# Troubleshooting
talosctl dashboard          # Talos system dashboard
kubectl get pods -A         # Show all pods
kubectl logs -n monitoring <pod-name>  # View pod logs
```

## Project Structure

```
talos/
├── docs/                          # Documentation
│   ├── Architecture.md            # System architecture
│   ├── Observability-Stack.md     # Monitoring setup
│   ├── IMPLEMENTATION_SUMMARY.md  # Implementation details
│   ├── TRAEFIK_IMPLEMENTATION.md  # Traefik configuration
│   ├── ProductRoadmap.md          # Future enhancements
│   └── troubleshooting/           # Historical fixes and solutions
├── infrastructure/
│   ├── talos/                     # Talos machine configs
│   ├── traefik/                   # Traefik configuration
│   │   ├── traefik-values.yaml    # Helm values
│   │   └── *-ingressroute.yaml    # IngressRoute definitions
│   ├── observability/             # Monitoring stack
│   │   ├── alloy-values.yaml      # Alloy configuration
│   │   ├── prometheus-*.yaml      # Prometheus manifests
│   │   ├── loki-*.yaml            # Loki manifests
│   │   └── grafana-*.yaml         # Grafana manifests
│   └── k8s/                       # Kubernetes resources
├── scripts/                       # Deployment scripts
│   ├── deploy-talos.sh            # Talos cluster setup
│   ├── deploy-traefik.sh          # Traefik deployment
│   └── deploy-observability.sh    # Monitoring deployment
├── examples/                      # Sample applications
│   ├── nodejs-app/                # Node.js example
│   ├── python-app/                # Python example
│   └── sample-app/                # Simple test app
├── Makefile                       # Convenience commands
└── README.md                      # This file
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -A

# View pod logs
kubectl logs -n <namespace> <pod-name>

# Describe pod for events
kubectl describe pod -n <namespace> <pod-name>
```

### No Logs in Loki

```bash
# Check Alloy is running
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy-logs

# View Alloy logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy-logs --tail=50

# Verify Loki is receiving data
kubectl exec -n monitoring <loki-pod> -- wget -qO- 'http://localhost:3100/loki/api/v1/label/namespace/values'
```

### Ingress Not Working

```bash
# Check Traefik is running
kubectl get pods -n traefik

# Verify socat proxies are running
docker ps | grep traefik-proxy

# Test direct access
curl -k https://traefik.local.dev/dashboard/
```

### PodSecurity Violations

Ensure namespaces that need elevated permissions are labeled:

```bash
kubectl label namespace <namespace> \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged
```

For more detailed troubleshooting, see [docs/troubleshooting/](docs/troubleshooting/).

## Key Features

### Automatic Service Discovery

Grafana Alloy automatically discovers and scrapes metrics from pods with these annotations:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

### Log Collection

Alloy automatically collects logs from all pods across all namespaces. View logs in Grafana:

1. Go to https://grafana.local.dev/
2. Click "Explore" in left menu
3. Select "Loki" datasource
4. Query example: `{namespace="default"}`

### Persistent Storage

Local-path-provisioner provides dynamic persistent volume provisioning:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
```

## Documentation

### For Developers (Start Here!)
- **[Developer Guide](docs/DEVELOPER_GUIDE.md)** - **Complete guide for developers** (rapid local testing, 60x faster than production workflow)
  - 5-minute quick start
  - kubectl, Helm, and ArgoCD deployment methods
  - Automatic observability setup
  - Common workflows and troubleshooting
  - **Save 2-4 hours per day** with local testing

### Technical Documentation
- **[Architecture](docs/Architecture.md)** - Detailed system design and component interactions
- **[Observability Stack](docs/Observability-Stack.md)** - Monitoring setup and configuration
- **[Traefik Implementation](docs/TRAEFIK_IMPLEMENTATION.md)** - Ingress controller details
- **[ArgoCD Local Deployment](infrastructure/argocd/README.md)** - GitOps workflows without Git
- **[Implementation Summary](docs/IMPLEMENTATION_SUMMARY.md)** - Project implementation notes
- **[Product Roadmap](docs/ProductRoadmap.md)** - Planned features and enhancements
- **[Troubleshooting](docs/troubleshooting/)** - Historical issues and solutions

## What's Included

### Monitoring Metrics (392+ available)

- Cluster metrics (nodes, pods, deployments)
- Container metrics (CPU, memory, network)
- Kubernetes API server metrics
- etcd metrics
- Custom application metrics (via annotations)

### Log Sources

- All pod logs across all namespaces
- Kubernetes events
- System logs from Talos nodes
- Application logs with automatic labeling

### Pre-configured Dashboards

Grafana includes datasources for:
- Prometheus (default) - Metrics visualization
- Loki - Log exploration and analysis

## Contributing

This is a local development platform. Feel free to customize and extend it for your needs.

## License

MIT

## Acknowledgments

Built with:
- [Talos Linux](https://www.talos.dev/) - Secure Kubernetes OS
- [Traefik](https://traefik.io/) - Cloud Native Application Proxy
- [Grafana Stack](https://grafana.com/) - Observability platform
- [Kubernetes](https://kubernetes.io/) - Container orchestration
