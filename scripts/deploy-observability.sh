#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INFRA_DIR="${SCRIPT_DIR}/../infrastructure/observability"

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

wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}

    log_info "Waiting for pods with label '$label' in namespace '$namespace' to be ready..."

    if kubectl wait --for=condition=ready pod \
        -l "$label" \
        -n "$namespace" \
        --timeout="${timeout}s" 2>/dev/null; then
        log_info "Pods are ready!"
        return 0
    else
        log_error "Pods failed to become ready within ${timeout} seconds"
        log_info "Pod status:"
        kubectl get pods -n "$namespace" -l "$label"
        log_info "Pod logs:"
        kubectl logs -n "$namespace" -l "$label" --tail=50 || true
        return 1
    fi
}

# Check if cluster is running
check_cluster() {
    log_step "Step 1: Checking cluster connectivity"

    if ! kubectl cluster-info &>/dev/null; then
        log_error "Kubernetes cluster is not accessible"
        log_info "Please ensure the Talos cluster is running:"
        log_info "  make deploy-infra"
        exit 1
    fi

    log_info "Cluster is accessible"
    kubectl get nodes
}

# Create monitoring namespace
create_namespace() {
    log_step "Step 2: Creating monitoring namespace"

    if kubectl get namespace monitoring &>/dev/null; then
        log_info "Namespace 'monitoring' already exists"
    else
        log_info "Creating namespace 'monitoring'..."
        kubectl create namespace monitoring
        kubectl label namespace monitoring name=monitoring
        log_info "Namespace created successfully"
    fi
}

# Deploy Prometheus
deploy_prometheus() {
    log_step "Step 3: Deploying Prometheus"

    log_info "Applying Prometheus manifests..."
    kubectl apply -f "${INFRA_DIR}/prometheus-pvc.yaml"
    kubectl apply -f "${INFRA_DIR}/prometheus-config.yaml"
    kubectl apply -f "${INFRA_DIR}/prometheus-deployment.yaml"
    kubectl apply -f "${INFRA_DIR}/prometheus-service.yaml"

    wait_for_pods "monitoring" "app=prometheus" 180

    log_info "Prometheus deployed successfully!"
}

# Deploy Loki
deploy_loki() {
    log_step "Step 4: Deploying Loki"

    log_info "Applying Loki manifests..."
    kubectl apply -f "${INFRA_DIR}/loki-pvc.yaml"
    kubectl apply -f "${INFRA_DIR}/loki-config.yaml"
    kubectl apply -f "${INFRA_DIR}/loki-deployment.yaml"
    kubectl apply -f "${INFRA_DIR}/loki-service.yaml"

    wait_for_pods "monitoring" "app=loki" 180

    log_info "Loki deployed successfully!"
}

# Deploy Grafana
deploy_grafana() {
    log_step "Step 5: Deploying Grafana"

    log_info "Applying Grafana manifests..."
    kubectl apply -f "${INFRA_DIR}/grafana-datasources.yaml"
    kubectl apply -f "${INFRA_DIR}/grafana-dashboards-config.yaml"
    kubectl apply -f "${INFRA_DIR}/grafana-dashboards.yaml"
    kubectl apply -f "${INFRA_DIR}/grafana-deployment.yaml"
    kubectl apply -f "${INFRA_DIR}/grafana-service.yaml"

    wait_for_pods "monitoring" "app=grafana" 180

    log_info "Grafana deployed successfully!"
}

# Deploy Grafana Alloy
deploy_alloy() {
    log_step "Step 6: Deploying Grafana Alloy"

    # Check if Helm is installed
    if ! command -v helm &>/dev/null; then
        log_error "Helm is not installed. Please install Helm first:"
        log_info "  https://helm.sh/docs/intro/install/"
        exit 1
    fi

    log_info "Installing Grafana Alloy via Helm..."
    chmod +x "${INFRA_DIR}/alloy-helm-install.sh"
    "${INFRA_DIR}/alloy-helm-install.sh"

    # Wait for Alloy to be ready
    sleep 5
    wait_for_pods "monitoring" "app.kubernetes.io/name=alloy" 180

    log_info "Grafana Alloy deployed successfully!"
}

# Verify deployment
verify_deployment() {
    log_step "Step 7: Verifying deployment"

    log_info "Checking all components..."
    echo ""

    log_info "Pods in monitoring namespace:"
    kubectl get pods -n monitoring -o wide
    echo ""

    log_info "Services in monitoring namespace:"
    kubectl get svc -n monitoring
    echo ""

    log_info "PersistentVolumeClaims in monitoring namespace:"
    kubectl get pvc -n monitoring
    echo ""

    # Check if all pods are running
    local failed_pods=$(kubectl get pods -n monitoring --no-headers | grep -v "Running\|Completed" | wc -l)

    if [ "$failed_pods" -gt 0 ]; then
        log_warn "Some pods are not in Running state"
        log_info "Run 'kubectl get pods -n monitoring' to check pod status"
        log_info "Run 'kubectl logs -n monitoring <pod-name>' to view logs"
    else
        log_info "All pods are running successfully!"
    fi
}

# Show access information
show_access_info() {
    log_step "Deployment Complete!"

    echo -e "${GREEN}Observability stack deployed successfully!${NC}\n"

    echo -e "${BLUE}Access Information:${NC}"
    echo -e "==================\n"

    echo -e "${GREEN}Grafana:${NC}"
    echo -e "  Port-forward:  ${YELLOW}kubectl port-forward -n monitoring svc/grafana 3000:3000${NC}"
    echo -e "  URL:          ${YELLOW}http://localhost:3000${NC}"
    echo -e "  Credentials:  ${YELLOW}admin / admin${NC}"
    echo -e "  (or use Makefile: ${YELLOW}make grafana-dashboard${NC})\n"

    echo -e "${GREEN}Prometheus:${NC}"
    echo -e "  Port-forward:  ${YELLOW}kubectl port-forward -n monitoring svc/prometheus 9090:9090${NC}"
    echo -e "  URL:          ${YELLOW}http://localhost:9090${NC}"
    echo -e "  (or use Makefile: ${YELLOW}make prometheus-ui${NC})\n"

    echo -e "${GREEN}Loki:${NC}"
    echo -e "  (Access via Grafana datasource)\n"

    echo -e "${GREEN}Grafana Alloy:${NC}"
    echo -e "  View logs:    ${YELLOW}kubectl logs -n monitoring -l app.kubernetes.io/name=alloy -f${NC}"
    echo -e "  (or use Makefile: ${YELLOW}make logs-alloy${NC})\n"

    echo -e "${BLUE}Quick Commands:${NC}"
    echo -e "===============\n"
    echo -e "  View all pods:        ${YELLOW}kubectl get pods -n monitoring${NC}"
    echo -e "  View Prometheus logs: ${YELLOW}make logs-prometheus${NC}"
    echo -e "  View Loki logs:       ${YELLOW}make logs-loki${NC}"
    echo -e "  View Alloy logs:      ${YELLOW}make logs-alloy${NC}"
    echo -e "  Destroy stack:        ${YELLOW}make destroy-observability${NC}\n"

    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "==========="
    echo -e "1. Port-forward to Grafana: ${YELLOW}make grafana-dashboard${NC}"
    echo -e "2. Deploy an application with Prometheus annotations"
    echo -e "3. Check metrics appear in Prometheus/Grafana"
    echo -e "4. View logs in Grafana Explore (Loki datasource)\n"
}

# Main execution
main() {
    log_info "Starting observability stack deployment..."
    log_info "This will deploy: Prometheus, Loki, Grafana, and Grafana Alloy"
    echo ""

    check_cluster
    create_namespace
    deploy_prometheus
    deploy_loki
    deploy_grafana
    deploy_alloy
    verify_deployment
    show_access_info
}

# Run main function
main
