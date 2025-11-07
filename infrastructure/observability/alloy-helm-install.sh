#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}[INFO]${NC} Installing Grafana Alloy via Helm..."

# Add Grafana Helm repository
echo -e "${GREEN}[INFO]${NC} Adding Grafana Helm repository..."
if ! helm repo list | grep -q "grafana"; then
    helm repo add grafana https://grafana.github.io/helm-charts
fi

# Update Helm repositories
echo -e "${GREEN}[INFO]${NC} Updating Helm repositories..."
helm repo update

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install or upgrade Grafana Alloy
echo -e "${GREEN}[INFO]${NC} Installing Grafana Alloy k8s-monitoring chart..."
helm upgrade --install alloy grafana/k8s-monitoring \
  --namespace monitoring \
  --create-namespace \
  --values "${SCRIPT_DIR}/alloy-values.yaml" \
  --version ^1 \
  --wait \
  --timeout 5m

echo -e "${GREEN}[SUCCESS]${NC} Grafana Alloy installed successfully!"

# Show deployment status
echo -e "\n${GREEN}[INFO]${NC} Alloy deployment status:"
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy

echo -e "\n${GREEN}[INFO]${NC} To view Alloy logs, run:"
echo -e "  kubectl logs -n monitoring -l app.kubernetes.io/name=alloy -f"
