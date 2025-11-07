# Architecture Documentation
# Talos Local Observability Platform

## Table of Contents
1. [System Overview](#system-overview)
2. [Component Architecture](#component-architecture)
3. [Data Flow](#data-flow)
4. [Network Architecture](#network-architecture)
5. [Storage Strategy](#storage-strategy)
6. [Service Discovery](#service-discovery)
7. [Deployment Strategy](#deployment-strategy)
8. [Technology Decisions](#technology-decisions)
9. [Integration Points](#integration-points)

---

## System Overview

The Talos Local Observability Platform provides a production-grade observability stack running locally on Talos Linux in Docker containers. It enables developers to test Kubernetes applications with full metrics and logs collection in an environment that mirrors production.

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Developer Machine                          │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                    Docker Runtime                              │ │
│  │                                                                │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │ │
│  │  │   Talos CP   │  │  Talos W1    │  │  Talos W2    │        │ │
│  │  │ (Control     │  │  (Worker 1)  │  │  (Worker 2)  │        │ │
│  │  │  Plane)      │  │              │  │              │        │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │ │
│  │         │                 │                 │                 │ │
│  │         └─────────────────┴─────────────────┘                 │ │
│  │                           │                                    │ │
│  │              ┌────────────▼────────────┐                      │ │
│  │              │  Kubernetes Cluster     │                      │ │
│  │              │                         │                      │ │
│  │              │  ┌──────────────────┐   │                      │ │
│  │              │  │ Traefik Ingress  │───┼───► :80/:443        │ │
│  │              │  └────────┬─────────┘   │                      │ │
│  │              │           │              │                      │ │
│  │              │  ┌────────▼─────────┐   │                      │ │
│  │              │  │ Grafana Alloy    │   │                      │ │
│  │              │  │ (k8s-monitoring) │   │                      │ │
│  │              │  │ • Metrics scrape │   │                      │ │
│  │              │  │ • Logs collect   │   │                      │ │
│  │              │  └───┬──────────┬───┘   │                      │ │
│  │              │      │          │       │                      │ │
│  │              │  ┌───▼─────┐ ┌─▼────┐  │                      │ │
│  │              │  │Prometheus│ │ Loki │  │                      │ │
│  │              │  └────┬─────┘ └──┬───┘  │                      │ │
│  │              │       │           │      │                      │ │
│  │              │  ┌────▼───────────▼──┐  │                      │ │
│  │              │  │     Grafana       │  │                      │ │
│  │              │  └───────────────────┘  │                      │ │
│  │              │                         │                      │ │
│  │              │  ┌───────────────────┐  │                      │ │
│  │              │  │ Sample Apps       │  │                      │ │
│  │              │  │ (with annotations)│  │                      │ │
│  │              │  └───────────────────┘  │                      │ │
│  │              └─────────────────────────┘                      │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Architecture Principles

1. **Containerization First**: All components run in Docker for consistency and portability
2. **Production Parity**: Use the same tools and configurations as production environments
3. **Auto-Discovery**: Zero-configuration service discovery via Kubernetes annotations
4. **Developer Experience**: One-command deployment with sensible defaults
5. **Observability Native**: Metrics and logs collection built-in from day one
6. **Cloud-Native Standards**: Follow CNCF and Kubernetes best practices

---

## Component Architecture

### 1. Infrastructure Layer

#### Talos Linux Nodes (Docker Containers)

**Control Plane Node** (`talos-cp-01`)
- Runs Kubernetes control plane components
- etcd for cluster state
- API server, scheduler, controller-manager
- Resources: 2 CPU, 4GB RAM

**Worker Nodes** (`talos-worker-01`, `talos-worker-02`)
- Run application workloads
- Kubelet and container runtime
- Resources: 2 CPU, 4GB RAM each

**Technology Choice**: Talos Linux
- Immutable OS designed for Kubernetes
- API-driven configuration (no SSH)
- Minimal attack surface
- Production-grade security by default

### 2. Kubernetes Layer

**Cluster Configuration**:
- Version: Latest stable (1.28+)
- CNI: Flannel (default with Talos)
- Service CIDR: 10.96.0.0/12
- Pod CIDR: 10.244.0.0/16

### 3. Ingress Layer

#### Traefik

**Purpose**: Provide predictable, developer-friendly endpoints

**Configuration**:
- Deployed as DaemonSet on worker nodes
- Listens on ports 80 (HTTP) and 443 (HTTPS)
- IngressRoute CRDs for service routing
- Automatic TLS with self-signed certificates

**Endpoints Exposed**:
- `grafana.local.dev` → Grafana UI
- `prometheus.local.dev` → Prometheus UI
- `*.local.dev` → Application endpoints

**DNS Resolution**:
- `/etc/hosts` entries OR
- dnsmasq for wildcard resolution

### 4. Observability Stack

#### Grafana Alloy

**Deployment**: Via k8s-monitoring Helm chart

**Purpose**: Universal telemetry collection agent

**Configuration**:
```
Alloy Components:
├── discovery.kubernetes
│   ├── Discover pods with annotations
│   └── Filter by prometheus.io/scrape=true
├── prometheus.scrape
│   ├── Scrape discovered targets
│   └── Respect prometheus.io/port & path
├── prometheus.remote_write
│   └── Send metrics to Prometheus
├── loki.source.kubernetes
│   ├── Collect pod logs
│   └── Enrich with metadata
└── loki.write
    └── Send logs to Loki
```

**Key Features**:
- Automatic service discovery
- Dynamic configuration
- No manual target management
- Support for custom relabeling

#### Prometheus

**Purpose**: Time-series metrics storage

**Configuration**:
- Retention: 15 days (configurable)
- Storage: 10GB PersistentVolume
- Scrape interval: Managed by Alloy (remote write)
- No direct scrape configs (Alloy handles discovery)

**Data Model**:
- Metrics from Alloy via remote write
- Labels preserved from Kubernetes metadata
- Service discovery labels added automatically

#### Loki

**Purpose**: Log aggregation system

**Configuration**:
- Retention: 7 days (configurable)
- Storage: 5GB PersistentVolume
- Index: BoltDB (single-node deployment)
- Chunks: Filesystem storage

**Log Pipeline**:
- Alloy collects pod logs
- Enriched with Kubernetes metadata
- Indexed by pod, namespace, container
- Queryable via LogQL in Grafana

#### Grafana

**Purpose**: Visualization and dashboards

**Configuration**:
- Pre-configured datasources (via provisioning)
- Variable-based datasource references
- Pre-loaded dashboards
- Anonymous access enabled (local dev)

**Datasource Configuration**:
```yaml
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    isDefault: true

  - name: Loki
    type: loki
    url: http://loki:3100
```

**Dashboard Strategy**:
- Use `${datasource}` variable for flexibility
- No hardcoded datasource UIDs
- Portable across environments

---

## Data Flow

### Metrics Flow

```
┌─────────────────┐
│  Application    │
│  with /metrics  │
│  endpoint       │
└────────┬────────┘
         │ expose :8080/metrics
         │
    ┌────▼─────────────────────────────┐
    │ Kubernetes Service Discovery     │
    │ (annotations)                    │
    │ • prometheus.io/scrape: true     │
    │ • prometheus.io/port: 8080       │
    │ • prometheus.io/path: /metrics   │
    └────┬─────────────────────────────┘
         │
    ┌────▼──────────┐
    │ Grafana Alloy │
    │ • Discovers   │
    │ • Scrapes     │
    │ • Relabels    │
    └────┬──────────┘
         │ remote_write
    ┌────▼──────────┐
    │  Prometheus   │
    │  (storage)    │
    └────┬──────────┘
         │ PromQL query
    ┌────▼──────────┐
    │    Grafana    │
    │  (dashboard)  │
    └───────────────┘
```

### Logs Flow

```
┌─────────────────┐
│  Application    │
│  stdout/stderr  │
└────────┬────────┘
         │
    ┌────▼─────────────┐
    │ Container Runtime│
    │ (logs to disk)   │
    └────┬─────────────┘
         │
    ┌────▼──────────┐
    │ Grafana Alloy │
    │ • Tails logs  │
    │ • Adds labels │
    │ • Filters     │
    └────┬──────────┘
         │ push
    ┌────▼──────────┐
    │     Loki      │
    │  (storage)    │
    └────┬──────────┘
         │ LogQL query
    ┌────▼──────────┐
    │    Grafana    │
    │  (explore)    │
    └───────────────┘
```

---

## Network Architecture

### Port Mappings

```
Docker Host
│
├── :6443 → Talos Control Plane (Kubernetes API)
├── :50000 → Talos Control Plane (Talos API)
├── :80 → Traefik (HTTP)
├── :443 → Traefik (HTTPS)
```

### Service Mesh (within K8s)

```
Kubernetes ClusterIP Services:
├── prometheus:9090 (internal only)
├── loki:3100 (internal only)
├── grafana:3000 → Traefik → grafana.local.dev
├── alloy:12345 (metrics endpoint)
└── app-svc:8080 → Traefik → app.local.dev
```

### DNS Strategy

**Option 1: /etc/hosts** (Simple)
```
127.0.0.1 grafana.local.dev
127.0.0.1 prometheus.local.dev
127.0.0.1 app.local.dev
```

**Option 2: dnsmasq** (Wildcard)
```
address=/local.dev/127.0.0.1
```

### Traffic Flow Example

```
Developer Browser
    │
    │ http://grafana.local.dev
    ▼
Docker Host :80
    │
    ▼
Traefik Pod
    │
    │ IngressRoute match: Host(`grafana.local.dev`)
    ▼
Grafana Service (ClusterIP)
    │
    ▼
Grafana Pod :3000
```

---

## Storage Strategy

### Persistent Volumes

**Prometheus Storage**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-path
```

**Loki Storage**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: loki-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path
```

**Storage Backend**:
- Docker volumes mounted to Talos worker nodes
- Survives pod restarts
- Cleared on cluster reset

**Retention Policies**:
- Prometheus: 15 days
- Loki: 7 days
- Adjustable via Helm values

---

## Service Discovery

### Annotation-Based Discovery

**Application Deployment Example**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: app
        image: sample-app:latest
        ports:
        - containerPort: 8080
```

### Alloy Discovery Configuration

```yaml
discovery.kubernetes "pods" {
  role = "pod"
}

discovery.relabel "filter_pods" {
  targets = discovery.kubernetes.pods.targets

  # Keep only pods with scrape annotation
  rule {
    source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
    action        = "keep"
    regex         = "true"
  }

  # Use custom port if specified
  rule {
    source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_port"]
    target_label  = "__address__"
    regex         = "(.+)"
    replacement   = "$1:${1}"
  }

  # Use custom path if specified
  rule {
    source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
    target_label  = "__metrics_path__"
    regex         = "(.+)"
  }
}

prometheus.scrape "pods" {
  targets    = discovery.relabel.filter_pods.output
  forward_to = [prometheus.remote_write.default.receiver]
}
```

### Automatic Label Enrichment

Alloy automatically adds:
- `namespace`: Kubernetes namespace
- `pod`: Pod name
- `container`: Container name
- `node`: Node name
- `job`: Derived from service name
- Custom labels from pod labels

---

## Deployment Strategy

### Deployment Order

```
Phase 1: Infrastructure
├── 1. Create Docker network
├── 2. Start Talos nodes (CP + Workers)
├── 3. Bootstrap Kubernetes cluster
└── 4. Verify cluster health

Phase 2: Storage & Networking
├── 5. Install local-path-provisioner
├── 6. Deploy Traefik
├── 7. Configure DNS (hosts file)
└── 8. Verify ingress

Phase 3: Observability Stack
├── 9. Deploy Prometheus (with PVC)
├── 10. Deploy Loki (with PVC)
├── 11. Deploy Grafana Alloy (k8s-monitoring chart)
├── 12. Deploy Grafana (with datasources)
└── 13. Import dashboards

Phase 4: Validation
├── 14. Deploy sample application
├── 15. Verify metrics collection
├── 16. Verify logs collection
└── 17. Access Grafana dashboards
```

### One-Command Deployment

**Makefile Target**:
```makefile
deploy: check-deps
	@echo "Deploying Talos Local Observability Platform..."
	@./scripts/deploy-talos.sh
	@./scripts/deploy-traefik.sh
	@./scripts/deploy-observability.sh
	@./scripts/deploy-sample-app.sh
	@echo "✅ Platform ready!"
	@make endpoints
```

### Dependency Checking

Before deployment, verify:
- Docker running
- kubectl installed
- helm installed
- talosctl installed
- Sufficient resources (CPU, RAM, disk)

---

## Technology Decisions

### Why Talos Linux?

**Pros**:
- Designed for Kubernetes (minimal, secure)
- API-driven (no SSH access needed)
- Immutable OS (consistent state)
- Production-grade security
- Easy Docker deployment

**Cons**:
- Learning curve (different from traditional Linux)
- Debugging requires API knowledge

**Decision**: Worth the trade-off for production parity and security.

### Why Grafana Alloy?

**Alternatives Considered**:
- Prometheus Operator + ServiceMonitors
- OpenTelemetry Collector
- Telegraf

**Chosen**: Grafana Alloy
- Unified agent (metrics + logs + traces)
- Native Kubernetes service discovery
- k8s-monitoring Helm chart (production-tested)
- Efficient resource usage
- Built-in relabeling and filtering

### Why Traefik?

**Alternatives Considered**:
- Nginx Ingress
- HAProxy Ingress
- Contour

**Chosen**: Traefik
- Dynamic configuration
- Native Kubernetes support
- Built-in dashboard
- Easy TLS management
- Lightweight for local dev

### Why Docker for Talos?

**Alternatives Considered**:
- VirtualBox VMs
- QEMU/KVM
- Cloud VMs

**Chosen**: Docker
- Fastest startup time
- Lowest resource overhead
- Cross-platform compatibility
- Familiar tooling

---

## Integration Points

### 1. Talos ↔ Kubernetes

**Interface**: Talos API
- Bootstrap cluster: `talosctl bootstrap`
- Get kubeconfig: `talosctl kubeconfig`
- Node configuration: `talosctl apply-config`

### 2. Alloy ↔ Kubernetes API

**Interface**: Kubernetes API (in-cluster)
- Service account with RBAC permissions
- Watch pods, services, endpoints
- Read annotations and labels

### 3. Alloy ↔ Prometheus

**Interface**: Remote Write Protocol
- Endpoint: `http://prometheus:9090/api/v1/write`
- Protocol: Snappy-compressed Protobuf
- Authentication: None (internal cluster)

### 4. Alloy ↔ Loki

**Interface**: Loki Push API
- Endpoint: `http://loki:3100/loki/api/v1/push`
- Protocol: JSON or Protobuf
- Batching: Configurable batch size

### 5. Grafana ↔ Datasources

**Interface**: HTTP APIs
- Prometheus: PromQL queries via `/api/v1/query`
- Loki: LogQL queries via `/loki/api/v1/query_range`
- Authentication: None (provisioned datasources)

### 6. Applications ↔ Alloy

**Interface**: HTTP scrape
- Endpoint: Defined by annotations
- Format: Prometheus exposition format
- Pull-based model

### 7. Traefik ↔ Kubernetes

**Interface**: Kubernetes API (watch CRDs)
- IngressRoute resources
- Middleware resources
- TLSOption resources

---

## Scalability Considerations

### Local Development Scope

**Current Design**:
- 1 control plane node
- 2 worker nodes
- Up to 50 pods
- 10-20 services

**Resource Limits**:
- Total: 6 CPU, 12GB RAM
- Suitable for: Microservices testing (3-5 apps)

### Scaling Options

**Horizontal Scaling** (within Docker):
- Add worker nodes: `docker run talos-worker-03`
- Update kubeconfig
- Limited by host resources

**Vertical Scaling**:
- Increase node resources in config
- Adjust Docker resource limits
- Monitor with `docker stats`

### Performance Optimization

1. **Metrics Cardinality**: Limit label combinations
2. **Log Volume**: Filter noisy logs in Alloy
3. **Storage**: Use faster Docker volumes (SSD)
4. **Scrape Intervals**: Balance freshness vs load

---

## Security Considerations

### Local Development Context

**Assumptions**:
- Trusted environment (developer machine)
- No sensitive data
- No external access

**Security Measures**:
- Talos: API access via local client certs
- Kubernetes: RBAC enabled (default)
- Grafana: Anonymous access (local only)
- No TLS for internal services (cluster network)

### Production Parity Gaps

**What's Different from Production**:
- No authentication on Grafana
- Self-signed certificates
- No network policies
- No pod security policies

**Recommendation**: Document these gaps for developers to understand production requirements.

---

## Troubleshooting Architecture

### Component Health Checks

```bash
# Talos nodes
talosctl health

# Kubernetes cluster
kubectl get nodes
kubectl get pods -A

# Alloy
kubectl logs -n monitoring -l app=alloy

# Prometheus
curl http://prometheus.local.dev/-/healthy

# Loki
curl http://loki:3100/ready

# Grafana
curl http://grafana.local.dev/api/health
```

### Common Issues

1. **Services not discovered**:
   - Check annotations on pods
   - Verify Alloy logs for scrape errors
   - Confirm RBAC permissions

2. **Metrics not appearing**:
   - Verify remote write config in Alloy
   - Check Prometheus targets: `http://prometheus.local.dev/targets`
   - Validate application metrics endpoint

3. **Logs not flowing**:
   - Check Loki ingestion: `kubectl logs -n monitoring loki-0`
   - Verify Alloy logs pipeline config
   - Check disk space (PVC full?)

---

## Future Architecture Enhancements

1. **Distributed Tracing**: Add Tempo for traces
2. **Alerting**: Integrate Alertmanager
3. **Multi-Cluster**: Support multiple K8s clusters
4. **GitOps**: Flux/ArgoCD for declarative config
5. **Service Mesh**: Istio/Linkerd integration
6. **Cost Estimation**: Resource usage → cloud cost projection

---

## Conclusion

This architecture provides a robust, production-like local Kubernetes environment with comprehensive observability. It balances developer experience (one-command deployment) with production parity (same tools and patterns), enabling confident local testing before deploying to production.

**Key Success Factors**:
- Auto-discovery reduces manual configuration
- Docker-based deployment ensures consistency
- Cloud-native tools mirror production setups
- Clear data flow enables troubleshooting
- Extensible design supports future enhancements
