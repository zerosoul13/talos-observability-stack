# Traefik Ingress Controller

This directory contains the Traefik ingress controller configuration for the Talos Local Observability Platform.

## Overview

Traefik provides predictable, developer-friendly endpoints for accessing services in the local Kubernetes cluster. It uses IngressRoute CRDs for advanced routing and HostPort for direct access without NodePort complexity.

## Architecture

```
Developer Browser
    │
    │ http://grafana.local.dev
    ▼
Docker Host :80 (HostPort)
    │
    ▼
Traefik DaemonSet (Worker Nodes)
    │
    │ IngressRoute: Host(`grafana.local.dev`)
    ▼
Grafana Service (ClusterIP)
    │
    ▼
Grafana Pod :3000
```

## Components

### 1. Traefik Helm Chart
- **File**: `traefik-values.yaml`
- **Deployment Type**: DaemonSet on worker nodes
- **Ports**: 80 (HTTP), 443 (HTTPS), 9000 (Dashboard)
- **Access Method**: HostPort for direct access
- **Resource Limits**: 500m CPU, 256Mi memory

### 2. IngressRoutes

#### Grafana IngressRoute
- **File**: `grafana-ingressroute.yaml`
- **Host**: `grafana.local.dev`
- **Backend**: `grafana.monitoring:3000`
- **Protocol**: HTTP

#### Prometheus IngressRoute
- **File**: `prometheus-ingressroute.yaml`
- **Host**: `prometheus.local.dev`
- **Backend**: `prometheus.monitoring:9090`
- **Protocol**: HTTP

#### Traefik Dashboard IngressRoute
- **File**: `traefik-dashboard-ingressroute.yaml`
- **Host**: `traefik.local.dev`
- **Backend**: Traefik API service (internal)
- **Protocol**: HTTP

### 3. DNS Configuration
- **File**: `setup-dns.sh`
- **Purpose**: Adds `.local.dev` entries to `/etc/hosts`
- **Entries**:
  - `127.0.0.1 grafana.local.dev`
  - `127.0.0.1 prometheus.local.dev`
  - `127.0.0.1 traefik.local.dev`
  - `127.0.0.1 app.local.dev`

### 4. Installation Script
- **File**: `traefik-helm-install.sh`
- **Purpose**: Installs Traefik via Helm with custom values
- **Features**:
  - Adds Traefik Helm repository
  - Creates namespace
  - Installs or upgrades release
  - Waits for pods to be ready

## Deployment

### Quick Start

Deploy Traefik with a single command:

```bash
make deploy-traefik
```

This will:
1. Check cluster connectivity
2. Install Traefik via Helm
3. Apply IngressRoute configurations
4. Configure DNS entries in `/etc/hosts`
5. Verify endpoints

### Manual Deployment

If you prefer manual deployment:

```bash
# 1. Install Traefik
cd infrastructure/traefik
bash traefik-helm-install.sh

# 2. Apply IngressRoutes
kubectl apply -f grafana-ingressroute.yaml
kubectl apply -f prometheus-ingressroute.yaml
kubectl apply -f traefik-dashboard-ingressroute.yaml

# 3. Setup DNS
sudo bash setup-dns.sh
```

## Configuration

### Traefik Helm Values

The `traefik-values.yaml` file contains the following key configurations:

```yaml
deployment:
  kind: DaemonSet  # Run on all worker nodes

nodeSelector:
  node-role.kubernetes.io/control-plane: ""  # Only worker nodes

ports:
  web:
    hostPort: 80  # Direct access via HostPort
  websecure:
    hostPort: 443

providers:
  kubernetesCRD:
    enabled: true  # Enable IngressRoute support
  kubernetesIngress:
    enabled: true  # Standard Ingress support

resources:
  limits:
    cpu: "500m"
    memory: "256Mi"
```

### IngressRoute Customization

To add a new IngressRoute for your application:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: default
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`my-app.local.dev`)
      kind: Rule
      services:
        - name: my-app-service
          port: 8080
```

Then add DNS entry:
```bash
echo "127.0.0.1 my-app.local.dev" | sudo tee -a /etc/hosts
```

## Verification

### Check Traefik Status

```bash
# View Traefik pods
kubectl get pods -n traefik

# View IngressRoutes
kubectl get ingressroute -A

# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik -f
```

### Test Endpoints

```bash
# Using Make
make test-endpoints

# Manual testing
curl -v http://traefik.local.dev
curl -v http://grafana.local.dev
curl -v http://prometheus.local.dev
```

### Access Services

Open in your browser:
- **Traefik Dashboard**: http://traefik.local.dev
- **Grafana**: http://grafana.local.dev (admin/admin)
- **Prometheus**: http://prometheus.local.dev

## Troubleshooting

### Issue: Endpoints not responding

**Symptoms**: `curl` returns connection refused or timeout

**Solutions**:
1. Check Traefik pods are running:
   ```bash
   kubectl get pods -n traefik
   ```

2. Verify IngressRoutes exist:
   ```bash
   kubectl get ingressroute -A
   ```

3. Check DNS resolution:
   ```bash
   cat /etc/hosts | grep local.dev
   ping -c 1 grafana.local.dev
   ```

4. Test direct pod access:
   ```bash
   kubectl port-forward -n monitoring svc/grafana 3000:3000
   curl http://localhost:3000
   ```

### Issue: DNS not resolving

**Symptoms**: `ping grafana.local.dev` fails

**Solutions**:
1. Verify `/etc/hosts` entries:
   ```bash
   grep local.dev /etc/hosts
   ```

2. Re-run DNS setup:
   ```bash
   sudo bash infrastructure/traefik/setup-dns.sh
   ```

3. Flush DNS cache:
   - **Linux**: `sudo systemd-resolve --flush-caches`
   - **macOS**: `sudo dscacheutil -flushcache`
   - **Windows**: `ipconfig /flushdns`

### Issue: Traefik pods not starting

**Symptoms**: Pods stuck in Pending or CrashLoopBackOff

**Solutions**:
1. Check node selector matches worker nodes:
   ```bash
   kubectl get nodes --show-labels | grep control-plane
   ```

2. Verify HostPort is not already in use:
   ```bash
   sudo netstat -tulpn | grep :80
   sudo netstat -tulpn | grep :443
   ```

3. Check pod events:
   ```bash
   kubectl describe pod -n traefik -l app.kubernetes.io/name=traefik
   ```

### Issue: IngressRoute not routing traffic

**Symptoms**: Traefik returns 404 or 502

**Solutions**:
1. Check IngressRoute status:
   ```bash
   kubectl describe ingressroute -n monitoring grafana
   ```

2. Verify backend service exists:
   ```bash
   kubectl get svc -n monitoring grafana
   ```

3. Check Traefik logs for routing errors:
   ```bash
   kubectl logs -n traefik -l app.kubernetes.io/name=traefik | grep -i error
   ```

4. Test service directly:
   ```bash
   kubectl port-forward -n monitoring svc/grafana 3000:3000
   ```

## Cleanup

### Remove Traefik (Keep DNS)

```bash
make destroy-traefik
```

### Remove Traefik and DNS entries

```bash
make destroy-traefik-full
```

### Manual Cleanup

```bash
# Delete IngressRoutes
kubectl delete -f infrastructure/traefik/grafana-ingressroute.yaml
kubectl delete -f infrastructure/traefik/prometheus-ingressroute.yaml
kubectl delete -f infrastructure/traefik/traefik-dashboard-ingressroute.yaml

# Uninstall Traefik
helm uninstall traefik -n traefik

# Remove DNS entries
sudo bash infrastructure/traefik/setup-dns.sh --remove
```

## Makefile Targets

| Command | Description |
|---------|-------------|
| `make deploy-traefik` | Deploy Traefik and configure DNS |
| `make destroy-traefik` | Remove Traefik (keep DNS) |
| `make destroy-traefik-full` | Remove Traefik and DNS |
| `make endpoints` | Show all accessible endpoints |
| `make test-endpoints` | Test endpoint accessibility |
| `make setup-dns` | Configure DNS only |
| `make logs-traefik` | View Traefik logs |
| `make traefik-status` | Show Traefik status |

## Security Considerations

### Local Development Context

This configuration is optimized for local development and makes trade-offs for convenience:

- **No TLS**: HTTP only (not HTTPS) for simplicity
- **No Authentication**: Traefik dashboard is publicly accessible
- **HostPort**: Binds to host network (less isolated)
- **No Network Policies**: Open communication between services

### Production Differences

In production, you should:
1. Enable TLS with Let's Encrypt or cert-manager
2. Configure authentication (BasicAuth, OAuth, etc.)
3. Use LoadBalancer or NodePort instead of HostPort
4. Implement Network Policies for service isolation
5. Enable rate limiting and access controls
6. Use external DNS instead of /etc/hosts

## Advanced Configuration

### Enable HTTPS with Self-Signed Certificates

1. Generate self-signed certificate:
   ```bash
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout tls.key -out tls.crt \
     -subj "/CN=*.local.dev"
   ```

2. Create TLS secret:
   ```bash
   kubectl create secret tls local-dev-tls \
     --cert=tls.crt --key=tls.key -n traefik
   ```

3. Update IngressRoute to use HTTPS:
   ```yaml
   spec:
     entryPoints:
       - websecure
     routes:
       - match: Host(`grafana.local.dev`)
         kind: Rule
         services:
           - name: grafana
             port: 3000
     tls:
       secretName: local-dev-tls
   ```

### Add Middleware (Rate Limiting, Headers, etc.)

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: traefik
spec:
  rateLimit:
    average: 100
    burst: 50
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`grafana.local.dev`)
      kind: Rule
      middlewares:
        - name: rate-limit
          namespace: traefik
      services:
        - name: grafana
          port: 3000
```

## References

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Traefik Kubernetes CRD](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/)
- [Helm Chart Values](https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml)
- [Talos Linux Ingress Guide](https://www.talos.dev/latest/kubernetes-guides/configuration/ingress/)
