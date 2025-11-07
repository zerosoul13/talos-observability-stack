#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
KEEP_DATA=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--keep-data] [--force]"
            echo "  --keep-data: Keep PersistentVolumeClaims (preserve data)"
            echo "  --force: Skip confirmation prompt"
            exit 1
            ;;
    esac
done

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

# Confirmation prompt
confirm_destruction() {
    if [ "$FORCE" = true ]; then
        return 0
    fi

    log_warn "This will destroy the entire observability stack!"

    if [ "$KEEP_DATA" = true ]; then
        log_info "PersistentVolumeClaims will be preserved (--keep-data flag)"
    else
        log_warn "All data (metrics and logs) will be permanently deleted!"
    fi

    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
}

# Remove Grafana Alloy
remove_alloy() {
    log_step "Removing Grafana Alloy"

    if helm list -n monitoring | grep -q "alloy"; then
        log_info "Uninstalling Grafana Alloy Helm release..."
        helm uninstall alloy -n monitoring || true
        log_info "Alloy removed successfully"
    else
        log_info "Alloy Helm release not found, skipping..."
    fi
}

# Remove Kubernetes resources
remove_resources() {
    log_step "Removing Kubernetes resources"

    if ! kubectl get namespace monitoring &>/dev/null; then
        log_info "Namespace 'monitoring' does not exist, nothing to remove"
        return 0
    fi

    log_info "Removing Grafana..."
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/grafana-service.yaml" --ignore-not-found=true
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/grafana-deployment.yaml" --ignore-not-found=true
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/grafana-dashboards.yaml" --ignore-not-found=true
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/grafana-dashboards-config.yaml" --ignore-not-found=true
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/grafana-datasources.yaml" --ignore-not-found=true

    log_info "Removing Loki..."
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/loki-service.yaml" --ignore-not-found=true
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/loki-deployment.yaml" --ignore-not-found=true
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/loki-config.yaml" --ignore-not-found=true

    log_info "Removing Prometheus..."
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/prometheus-service.yaml" --ignore-not-found=true
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/prometheus-deployment.yaml" --ignore-not-found=true
    kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/prometheus-config.yaml" --ignore-not-found=true

    if [ "$KEEP_DATA" = false ]; then
        log_info "Removing PersistentVolumeClaims (data will be deleted)..."
        kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/loki-pvc.yaml" --ignore-not-found=true
        kubectl delete -f "${SCRIPT_DIR}/../infrastructure/observability/prometheus-pvc.yaml" --ignore-not-found=true
    else
        log_info "Keeping PersistentVolumeClaims (data preserved)"
    fi

    # Wait for pods to terminate
    log_info "Waiting for pods to terminate..."
    kubectl wait --for=delete pod -l app=prometheus -n monitoring --timeout=60s 2>/dev/null || true
    kubectl wait --for=delete pod -l app=loki -n monitoring --timeout=60s 2>/dev/null || true
    kubectl wait --for=delete pod -l app=grafana -n monitoring --timeout=60s 2>/dev/null || true

    log_info "Resources removed successfully"
}

# Optionally remove namespace
remove_namespace() {
    log_step "Cleaning up namespace"

    if ! kubectl get namespace monitoring &>/dev/null; then
        log_info "Namespace 'monitoring' does not exist"
        return 0
    fi

    # Check if namespace has any remaining resources
    local remaining_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)

    if [ "$remaining_pods" -eq 0 ]; then
        if [ "$KEEP_DATA" = false ]; then
            log_info "Deleting monitoring namespace..."
            kubectl delete namespace monitoring --timeout=60s || true
            log_info "Namespace deleted"
        else
            log_info "Keeping namespace (PVCs are preserved)"
        fi
    else
        log_warn "Namespace still has $remaining_pods pod(s), not deleting namespace"
        log_info "Run 'kubectl get pods -n monitoring' to see remaining pods"
    fi
}

# Show final status
show_status() {
    log_step "Destruction Complete"

    echo -e "${GREEN}Observability stack removed successfully!${NC}\n"

    if [ "$KEEP_DATA" = true ]; then
        echo -e "${YELLOW}Note: PersistentVolumeClaims were preserved${NC}"
        echo -e "To view remaining PVCs:"
        echo -e "  ${BLUE}kubectl get pvc -n monitoring${NC}\n"
        echo -e "To delete PVCs manually:"
        echo -e "  ${BLUE}kubectl delete pvc -n monitoring prometheus-pvc loki-pvc${NC}\n"
    fi

    if kubectl get namespace monitoring &>/dev/null; then
        echo -e "${YELLOW}Note: Namespace 'monitoring' still exists${NC}"
        echo -e "To delete the namespace:"
        echo -e "  ${BLUE}kubectl delete namespace monitoring${NC}\n"
    fi

    echo -e "To redeploy the observability stack:"
    echo -e "  ${BLUE}make deploy-observability${NC}\n"
}

# Main execution
main() {
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    log_info "Starting observability stack destruction..."
    echo ""

    confirm_destruction
    remove_alloy
    remove_resources
    remove_namespace
    show_status
}

# Run main function
main
