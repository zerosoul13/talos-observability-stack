# ArgoCD Sample Application

This is a simple nginx application to demonstrate deploying from local folders using ArgoCD.

## Deploy this application with ArgoCD

### Method 1: Direct Application (ConfigMap approach)

```bash
# 1. Create the application directly from these manifests
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-nginx
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-username/your-repo.git
    path: examples/argocd-sample-app
    targetRevision: HEAD
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

### Method 2: Local Folder Deployment (ConfigMap)

```bash
# 1. Create a ConfigMap from this folder
kubectl create configmap sample-app-manifests \
  --from-file=. \
  --namespace=argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Create the Application (note: this is experimental)
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-nginx-local
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

### Method 3: Just apply directly (simplest for local testing)

```bash
kubectl apply -f deployment.yaml
```

## Access the application

After deployment:

1. Add to `/etc/hosts`:
   ```
   127.0.0.1 sample.local.dev
   ```

2. Access at: https://sample.local.dev/

## Verify deployment

```bash
# Check pods
kubectl get pods -n sample-app

# Check service
kubectl get svc -n sample-app

# Check IngressRoute
kubectl get ingressroute -n sample-app

# Test endpoint
curl https://sample.local.dev/ -k
```

## Clean up

```bash
kubectl delete namespace sample-app
# Or via ArgoCD
kubectl delete application sample-nginx -n argocd
```
