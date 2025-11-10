# Talos Grafana Alloy Platform

**A production-ready Grafana Alloy testing platform on Talos Linux with self-monitoring observability stack.**

## 🎯 What is This?

A complete, ready-to-go **Grafana Alloy** platform that allows you to test and explore Alloy's capabilities without complexity. Deploy a full observability stack in under 5 minutes and immediately see Alloy in action collecting metrics and logs from Prometheus, Loki, and Grafana **monitoring themselves**.

### Key Highlights

✅ **Grafana Alloy Operator** - Full CRD-based Alloy deployment and management  

✅ **Self-Monitoring Demo** - Custom Alloy collectors monitoring the observability stack itself  

✅ **Production-Ready** - Talos Linux + Kubernetes v1.31.1  

✅ **Zero Complexity** - No ingress setup, no DNS hacks, just pure Alloy power  

✅ **5-Minute Setup** - From zero to full stack with self-monitoring

## 🚀 Quick Start

### Prerequisites

- **Docker Desktop or Docker Engine** (20.10+)
- **kubectl** (1.28+)
- **helm** (3.12+)
- **talosctl** - Install with: `curl -sL https://talos.dev/install | sh`

**System Requirements:**
- Minimum: 8GB RAM, 4 CPU cores
- Recommended: 16GB RAM, 8 CPU cores

### Deploy in 2 Commands

```bash
# 1. Deploy Talos cluster (3-5 minutes)
make deploy-infra

# 2. Deploy observability stack with Alloy (2-3 minutes)
make deploy-observability
```

### Access Your Stack

```bash
# Open Grafana Dashboard
make grafana-dashboard
# Navigate to http://localhost:3000
# Login: admin / admin

# Open Prometheus UI
make prometheus-ui
# Navigate to http://localhost:9090
```

That's it! You now have a complete Alloy platform with self-monitoring running.

## 🎨 Architecture

### The Platform

```
┌─────────────────────────────────────────────────────────────┐
│                    Talos Kubernetes Cluster                 │
│                     (Native Docker Mode)                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Grafana Alloy Operator                       │
│          (Manages all Alloy Custom Resources)                │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Alloy Metrics│    │ Alloy Logs   │    │Alloy Singleton│
│ (StatefulSet)│    │ (DaemonSet)  │    │ (Deployment) │
└──────────────┘    └──────────────┘    └──────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Custom Alloy Self-Monitoring                    │
│  • prometheus-observability (scrapes Prometheus)             │
│  • loki-exporter (scrapes Loki)                             │
│  • grafana-exporter (scrapes Grafana)                       │
│                                                              │
│  All metrics labeled as "integrations/unix"                  │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Prometheus  │    │     Loki     │    │   Grafana    │
│   (Metrics)  │    │    (Logs)    │    │ (Dashboards) │
└──────────────┘    └──────────────┘    └──────────────┘
```

### Alloy Components Deployed

| Component | Type | Purpose |
|-----------|------|---------|
| **Alloy Operator** | Deployment | Manages Alloy CRs and lifecycle |
| **Alloy Metrics** | StatefulSet | Collects cluster and pod metrics |
| **Alloy Logs** | DaemonSet | Collects logs from all nodes |
| **Alloy Singleton** | Deployment | Handles cluster-wide events |
| **Alloy Node Exporter** | DaemonSet | Node-level system metrics |
| **Kube State Metrics** | Deployment | Kubernetes object metrics |

### Custom Self-Monitoring Alloy Collectors

Three custom Alloy instances demonstrate advanced Alloy configuration:

#### 1. Prometheus Self-Monitoring
```yaml
# File: infrastructure/observability/prometheus-observability.yaml
apiVersion: collectors.grafana.com/v1alpha1
kind: Alloy
metadata:
  name: prometheus-observability
spec:
  alloy:
    configMap:
      content: |-
        # Discovers Prometheus pods
        # Scrapes /metrics endpoint
        # Relabels to job="integrations/unix"
        # Sends to Prometheus remote_write
```

#### 2. Loki Self-Monitoring
```yaml
# File: infrastructure/observability/loki-observability.yaml
apiVersion: collectors.grafana.com/v1alpha1
kind: Alloy
metadata:
  name: loki-exporter
spec:
  alloy:
    configMap:
      content: |-
        # Discovers Loki pods
        # Scrapes /metrics endpoint
        # Relabels to job="integrations/unix"
        # Sends to Prometheus remote_write
```

#### 3. Grafana Self-Monitoring
```yaml
# File: infrastructure/observability/grafana-observability.yaml
apiVersion: collectors.grafana.com/v1alpha1
kind: Alloy
metadata:
  name: grafana-exporter
spec:
  alloy:
    configMap:
      content: |-
        # Discovers Grafana pods
        # Scrapes /metrics endpoint
        # Relabels to job="integrations/unix"
        # Sends to Prometheus remote_write
```

## 📊 Exploring Alloy in Action

### View All Alloy Instances

```bash
# See all Alloy custom resources
kubectl get alloys -n monitoring

# Expected output:
# NAME                       AGE
# alloy-logs                 5m
# alloy-metrics              5m
# alloy-singleton            5m
# grafana-exporter           3m
# loki-exporter              3m
# prometheus-observability   3m
```

### Check Self-Monitoring Metrics in Grafana

1. Open Grafana: `make grafana-dashboard`
2. Go to **Explore** → **Prometheus**
3. Query: `{job="integrations/unix"}`
4. See metrics from Prometheus, Loki, and Grafana!

### View Alloy Logs

```bash
# All Alloy instances
make logs-alloy

# Specific Alloy instance
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy-metrics -f
```

### Inspect Alloy Configuration

```bash
# View Prometheus self-monitoring config
kubectl get alloy prometheus-observability -n monitoring -o yaml

# View the actual Alloy config
kubectl get alloy prometheus-observability -n monitoring \
  -o jsonpath='{.spec.alloy.configMap.content}'
```

## 🛠️ Common Commands

### Cluster Management
```bash
make deploy-infra           # Deploy Talos cluster
make destroy-infra          # Destroy Talos cluster
make status                 # Show cluster status
make health                 # Check cluster health
make restart                # Destroy and redeploy cluster
```

### Observability Stack
```bash
make deploy-observability   # Deploy full stack + self-monitoring
make destroy-observability  # Destroy observability stack
make monitoring-status      # Show all monitoring components
```

### Access Services
```bash
make grafana-dashboard      # Port-forward to Grafana (localhost:3000)
make prometheus-ui          # Port-forward to Prometheus (localhost:9090)
```

### View Logs
```bash
make logs-prometheus        # Prometheus logs
make logs-loki              # Loki logs
make logs-alloy             # All Alloy instances logs
```

### Kubernetes Queries
```bash
make nodes                  # List cluster nodes
make pods                   # List all pods
make services               # List all services
make events                 # Recent cluster events
```

## 📁 Project Structure

```
talos/
├── infrastructure/
│   └── observability/                    # All observability configs
│       ├── alloy-values.yaml             # Main Alloy Helm values
│       ├── alloy-helm-install.sh         # Alloy deployment script
│       ├── prometheus-*.yaml             # Prometheus manifests
│       ├── loki-*.yaml                   # Loki manifests
│       ├── grafana-*.yaml                # Grafana manifests
│       ├── prometheus-observability.yaml  # ⭐ Demo: Prometheus self-monitoring
│       ├── loki-observability.yaml        # ⭐ Demo: Loki self-monitoring
│       └── grafana-observability.yaml     # ⭐ Demo: Grafana self-monitoring
├── scripts/
│   ├── deploy-talos-native.sh           # Cluster deployment
│   ├── destroy-talos-native.sh          # Cluster teardown
│   ├── deploy-observability.sh          # Stack + self-monitoring deployment
│   ├── destroy-observability.sh         # Stack teardown
│   └── status-talos.sh                  # Health checks
├── docs/                                # Documentation
│   ├── Architecture.md                  # System design
│   ├── Observability-Stack.md           # Monitoring details
│   ├── DEVELOPER_GUIDE.md               # Developer workflows
│   └── ProductRoadmap.md                # Future features
├── Makefile                             # Convenience commands
└── README.md                            # This file
```

## 🎓 Learning Alloy

This platform is perfect for learning and testing Grafana Alloy because:

### 1. See Real Alloy Configurations
All Alloy configs are in Kubernetes CRs you can inspect:
```bash
kubectl get alloys -n monitoring -o yaml
```

### 2. Experiment with Custom Collectors
The three self-monitoring collectors are templates you can modify:
- Edit the YAML files in `infrastructure/observability/`
- Apply changes: `kubectl apply -f <file>`
- See results immediately in Grafana

### 3. Understand Alloy Architecture
- **Operator Pattern**: See how Alloy Operator manages instances
- **DaemonSet**: Node-level collection with `alloy-logs`
- **StatefulSet**: Cluster metrics with `alloy-metrics`
- **Deployment**: Singleton tasks with `alloy-singleton`

### 4. Prometheus Remote Write
All custom collectors demonstrate Prometheus remote_write:
```
prometheus.remote_write "target" {
  endpoint {
    url = "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/write"
  }
}
```

## 🔧 Customization

### Add Your Own Alloy Collector

Create a new Alloy CR:

```yaml
# my-custom-collector.yaml
apiVersion: collectors.grafana.com/v1alpha1
kind: Alloy
metadata:
  name: my-collector
  namespace: monitoring
spec:
  alloy:
    configMap:
      content: |-
        discovery.kubernetes "my_targets" {
          role = "pod"
          selectors {
            role = "pod"
            label = "app=my-app"
          }
        }

        prometheus.scrape "my_app" {
          targets    = discovery.kubernetes.my_targets.targets
          forward_to = [prometheus.remote_write.prom.receiver]
        }

        prometheus.remote_write "prom" {
          endpoint {
            url = "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/write"
          }
        }
```

Deploy it:
```bash
kubectl apply -f my-custom-collector.yaml
```

### Modify Alloy Configuration

Edit the main Alloy values:
```bash
vim infrastructure/observability/alloy-values.yaml
```

Redeploy:
```bash
make destroy-observability
make deploy-observability
```

## 🐛 Troubleshooting

### Alloy Pods Not Running

```bash
# Check Alloy operator
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy-operator

# Check Alloy instances
kubectl get alloys -n monitoring

# View specific Alloy status
kubectl describe alloy alloy-metrics -n monitoring
```

### No Self-Monitoring Metrics

```bash
# Verify custom Alloy collectors exist
kubectl get alloys -n monitoring | grep -E "prometheus-observability|loki-exporter|grafana-exporter"

# Check collector logs
kubectl logs -n monitoring -l app.kubernetes.io/instance=prometheus-observability

# Verify Prometheus is receiving data
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090
# Query: {job="integrations/unix"}
```

### Pods Stuck in Pending

```bash
# Check PodSecurity namespace labels
kubectl get namespace monitoring -o yaml | grep pod-security

# Should see: pod-security.kubernetes.io/enforce=privileged
# If not, the deployment script will fix this automatically
```

## 📚 Documentation

- **[Architecture](docs/Architecture.md)** - System design and components
- **[Observability Stack](docs/Observability-Stack.md)** - Monitoring setup details
- **[Developer Guide](docs/DEVELOPER_GUIDE.md)** - Development workflows
- **[Product Roadmap](docs/ProductRoadmap.md)** - Planned features

## 🎯 Use Cases

### For Grafana Alloy Users
- **Test Alloy configurations** in a safe local environment
- **Learn Alloy's CR-based deployment** model
- **Experiment with different collectors** (DaemonSet, StatefulSet, Deployment)
- **Understand Prometheus remote_write** integration

### For Platform Engineers
- **Evaluate Alloy** for production use
- **Test custom collectors** before production deployment
- **Prototype monitoring solutions** quickly
- **Validate Alloy Operator** behavior

### For Developers
- **Local Kubernetes development** with full observability
- **Test application metrics** collection
- **Debug log collection** issues
- **Validate Prometheus annotations**

## 🌟 What Makes This Special?

1. **Alloy-First Design**: Built specifically to showcase Grafana Alloy
2. **Self-Monitoring**: Observability stack monitors itself out-of-the-box
3. **Production-Ready**: Talos Linux provides a real Kubernetes environment
4. **Zero Complexity**: No ingress, no DNS, no external dependencies
5. **Educational**: Learn by exploring real Alloy configurations
6. **Fast Iteration**: Destroy and redeploy in under 3 minutes

## 🤝 Contributing

This is a learning and testing platform. Feel free to:
- Add more custom Alloy collectors
- Extend the self-monitoring capabilities
- Create additional dashboards
- Share your Alloy configurations

## 📝 License

MIT

## 🙏 Acknowledgments

Built with:
- [Grafana Alloy](https://grafana.com/docs/alloy/) - Unified observability collector
- [Talos Linux](https://www.talos.dev/) - Secure Kubernetes OS
- [Prometheus](https://prometheus.io/) - Metrics and monitoring
- [Loki](https://grafana.com/oss/loki/) - Log aggregation
- [Grafana](https://grafana.com/) - Observability visualization
- [Kubernetes](https://kubernetes.io/) - Container orchestration

---

**Ready to explore Grafana Alloy?**

```bash
make deploy-infra
make deploy-observability
make grafana-dashboard
```

Happy monitoring! 🎉
