#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="talos-local"
KUBERNETES_VERSION="1.31.1"
WORKERS=1

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

main() {
    log_info "Deploying Talos cluster using native Docker support..."
    echo

    # Check if cluster containers actually exist (not just metadata)
    if docker ps -a --filter "name=talos-local" --format "{{.Names}}" | grep -q "talos-local"; then
        log_warn "Cluster '${CLUSTER_NAME}' containers already exist"
        log_warn "Destroy it first with: make destroy-infra"
        exit 1
    fi

    # Create cluster - talosctl handles EVERYTHING
    log_info "Creating cluster (this takes 3-5 minutes)..."
    talosctl cluster create \
        --name "${CLUSTER_NAME}" \
        --kubernetes-version "${KUBERNETES_VERSION}" \
        --workers ${WORKERS} \
        --controlplanes 1 \
        --wait \
        --wait-timeout 10m

    log_info "Cluster created successfully!"
    echo

    # Summary
    log_info "================================================================"
    log_info "Talos Cluster Ready!"
    log_info "================================================================"
    echo
    log_info "Cluster Nodes:"
    kubectl get nodes -o wide
    echo
    log_info "Useful Commands:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    echo "  talosctl --context ${CLUSTER_NAME} dashboard"
    echo "  talosctl --context ${CLUSTER_NAME} health"
    echo
    log_info "Next Steps:"
    echo "  make deploy-observability     # Deploy monitoring stack"
    echo
    log_info "To destroy: talosctl cluster destroy --name ${CLUSTER_NAME}"
    log_info "================================================================"
}

main "$@"
