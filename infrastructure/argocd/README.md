# ArgoCD Local Development Setup

This directory contains ArgoCD configuration for deploying applications from local folders.

## Overview

ArgoCD is configured to deploy applications from:
1. **Git repositories** (standard ArgoCD usage)
2. **Local folders** (for local development)

## Accessing ArgoCD

### Web UI
- **URL**: https://argocd.local.dev/
- **Username**: `admin`
- **Password**: Get with: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`

### CLI
```bash
# Install ArgoCD CLI (optional)
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Login
argocd login argocd.local.dev --grpc-web

# Or get password for UI login
make argocd-password
```

## Deploying from Local Folders

### Method 1: Using ConfigMaps (Recommended for small apps)

This is the simplest way to deploy local manifests:

```bash
# 1. Create a ConfigMap from your local folder
kubectl create configmap my-app-manifests \
  --from-file=./my-app/ \
  --namespace=argocd

# 2. Create an Application that references the ConfigMap
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ''
    path: ''
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

### Method 2: Using PVC (For larger apps or frequent updates)

```bash
# 1. Copy your manifests to the PVC
kubectl run -it --rm copy-to-pvc \
  --image=busybox \
  --restart=Never \
  --namespace=argocd \
  -- sh -c "mkdir -p /mnt/local-apps/my-app"

kubectl cp ./my-app argocd/copy-to-pvc:/mnt/local-apps/my-app

# 2. Create an Application pointing to the PVC path
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-from-pvc
  namespace: argocd
spec:
  project: default
  source:
    repoURL: file:///mnt/local-apps
    path: my-app
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

### Method 3: Using Git (Traditional ArgoCD)

```bash
# Deploy from a Git repository
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-from-git
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo.git
    path: kubernetes/manifests
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

## Example: Deploying a Sample App

Let's deploy the sample Node.js app from the examples folder:

```bash
# 1. Create a namespace for the app
kubectl create namespace sample-app

# 2. Create ConfigMap from local manifests
kubectl create configmap sample-app-manifests \
  --from-file=../../examples/nodejs-app/ \
  --namespace=argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Create ArgoCD Application
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-nodejs-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ''
    path: ''
  destination:
    server: https://kubernetes.default.svc
    namespace: sample-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

## Updating Applications

### When using ConfigMaps:
```bash
# Update the ConfigMap with new manifests
kubectl create configmap my-app-manifests \
  --from-file=./my-app/ \
  --namespace=argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# Trigger sync in ArgoCD
argocd app sync my-app
# Or via UI: Click "Sync" button
```

### When using PVC:
```bash
# 1. Copy updated files
kubectl cp ./my-app argocd/<pod-with-pvc-mount>:/mnt/local-apps/my-app

# 2. ArgoCD will auto-sync if configured
# Or manually: argocd app sync my-app-from-pvc
```

## Troubleshooting

### Check ArgoCD Server Logs
```bash
kubectl logs -n argocd deployment/argocd-server -f
```

### Check Repo Server Logs
```bash
kubectl logs -n argocd deployment/argocd-repo-server -f
```

### Check Application Status
```bash
kubectl get application -n argocd
kubectl describe application my-app -n argocd
```

### View Application in CLI
```bash
argocd app get my-app
argocd app sync my-app
argocd app logs my-app
```

## Files

- `argocd-ingressroute.yaml` - Traefik ingress for ArgoCD UI
- `local-apps-pvc.yaml` - PVC for storing local app manifests
- `argocd-repo-server-patch.yaml` - Mounts PVC to repo-server
- `argocd-cm-local.yaml` - ConfigMap for local app support

## Best Practices for Local Development

1. **Use ConfigMaps for small apps** - Easier to update, no PVC management
2. **Use PVC for larger apps** - Better for apps with many files
3. **Use Git for production-like testing** - Most similar to real deployments
4. **Enable auto-sync** - Automatically deploy changes
5. **Use namespaces** - Keep apps isolated

## Common Makefile Commands

```bash
make argocd-password      # Get admin password
make argocd-apps          # List all applications
make argocd-sync APP=name # Sync specific application
```

## Links

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Application Spec](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications)
