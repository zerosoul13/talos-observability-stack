#!/bin/bash
set -e

# Traefik Helm Installation Script
# Installs Traefik ingress controller using Helm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAEFIK_NAMESPACE="traefik"
HELM_RELEASE_NAME="traefik"
TRAEFIK_CHART_VERSION="v2.10.7"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}[INFO]${NC} Starting Traefik installation..."

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Helm is not installed. Please install Helm first."
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Adding Traefik Helm repository..."
helm repo add traefik https://traefik.github.io/charts || true
helm repo update

echo -e "${GREEN}[INFO]${NC} Creating namespace: ${TRAEFIK_NAMESPACE}..."
kubectl create namespace ${TRAEFIK_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Check if Traefik is already installed
if helm list -n ${TRAEFIK_NAMESPACE} | grep -q ${HELM_RELEASE_NAME}; then
    echo -e "${YELLOW}[WARN]${NC} Traefik is already installed. Upgrading..."
    helm upgrade ${HELM_RELEASE_NAME} traefik/traefik \
        --namespace ${TRAEFIK_NAMESPACE} \
        --values "${SCRIPT_DIR}/traefik-values.yaml" \
        --wait \
        --timeout 5m
else
    echo -e "${GREEN}[INFO]${NC} Installing Traefik via Helm..."
    helm install ${HELM_RELEASE_NAME} traefik/traefik \
        --namespace ${TRAEFIK_NAMESPACE} \
        --values "${SCRIPT_DIR}/traefik-values.yaml" \
        --create-namespace \
        --wait \
        --timeout 5m
fi

echo -e "${GREEN}[INFO]${NC} Waiting for Traefik pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=traefik \
    -n ${TRAEFIK_NAMESPACE} \
    --timeout=300s

echo -e "${GREEN}[INFO]${NC} Verifying Traefik installation..."
kubectl get pods -n ${TRAEFIK_NAMESPACE} -l app.kubernetes.io/name=traefik

echo -e "${GREEN}[SUCCESS]${NC} Traefik installed successfully!"
echo ""
echo "Traefik Dashboard: http://traefik.local.dev (after DNS setup)"
echo "HTTP Port: 80"
echo "HTTPS Port: 443"
echo ""
echo "To view Traefik logs:"
echo "  kubectl logs -n ${TRAEFIK_NAMESPACE} -l app.kubernetes.io/name=traefik -f"
