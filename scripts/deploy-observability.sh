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
        # Ensure PodSecurity labels are set for ephemeral cluster
        kubectl label namespace monitoring pod-security.kubernetes.io/enforce=privileged --overwrite
        kubectl label namespace monitoring pod-security.kubernetes.io/audit=privileged --overwrite
        kubectl label namespace monitoring pod-security.kubernetes.io/warn=privileged --overwrite
        log_info "Updated PodSecurity labels for ephemeral cluster usage"
    else
        log_info "Creating namespace 'monitoring'..."
        kubectl create namespace monitoring
        kubectl label namespace monitoring name=monitoring
        # Set privileged PodSecurity for ephemeral cluster (node-exporter needs host access)
        kubectl label namespace monitoring pod-security.kubernetes.io/enforce=privileged
        kubectl label namespace monitoring pod-security.kubernetes.io/audit=privileged
        kubectl label namespace monitoring pod-security.kubernetes.io/warn=privileged
        log_info "Namespace created successfully with privileged PodSecurity (ephemeral cluster)"
    fi
}

# Deploy Prometheus
deploy_prometheus() {
    log_step "Step 3: Deploying Prometheus"

    if kubectl get deployment prometheus -n monitoring &>/dev/null && \
       kubectl get deployment prometheus -n monitoring -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
        log_info "Prometheus deployment already exists and is ready, skipping deployment."
    else
        log_info "Applying Prometheus manifests..."
        kubectl apply -f "${INFRA_DIR}/prometheus-config.yaml"
        kubectl apply -f "${INFRA_DIR}/prometheus-deployment.yaml"
        kubectl apply -f "${INFRA_DIR}/prometheus-service.yaml"

        wait_for_pods "monitoring" "app=prometheus" 180

        log_info "Prometheus deployed successfully!"
    fi
}

# Deploy Loki
deploy_loki() {
    log_step "Step 4: Deploying Loki"

    if kubectl get deployment loki -n monitoring &>/dev/null && \
       kubectl get deployment loki -n monitoring -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
        log_info "Loki deployment already exists and is ready, skipping deployment."
    else
        log_info "Applying Loki manifests..."
        kubectl apply -f "${INFRA_DIR}/loki-config.yaml"
        kubectl apply -f "${INFRA_DIR}/loki-deployment.yaml"
        kubectl apply -f "${INFRA_DIR}/loki-service.yaml"

        wait_for_pods "monitoring" "app=loki" 180

        log_info "Loki deployed successfully!"
    fi
}

# Deploy Grafana
deploy_grafana() {
    log_step "Step 5: Deploying Grafana"

    if kubectl get deployment grafana -n monitoring &>/dev/null && \
       kubectl get deployment grafana -n monitoring -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
        log_info "Grafana deployment already exists and is ready, skipping deployment."
    else
        log_info "Applying Grafana manifests..."
        kubectl apply -f "${INFRA_DIR}/grafana-datasources.yaml"
        kubectl apply -f "${INFRA_DIR}/grafana-dashboards-config.yaml"
        kubectl apply -f "${INFRA_DIR}/grafana-dashboards.yaml"
        kubectl apply -f "${INFRA_DIR}/grafana-deployment.yaml"
        kubectl apply -f "${INFRA_DIR}/grafana-service.yaml"

        wait_for_pods "monitoring" "app=grafana" 180

        log_info "Grafana deployed successfully!"
    fi
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

    # Wait for Alloy Operator to be ready
    sleep 5
    wait_for_pods "monitoring" "app.kubernetes.io/name=alloy-operator" 180

    # Wait for Alloy instances to be created and ready
    log_info "Waiting for Alloy instances to be created..."
    sleep 10

    log_info "Checking Alloy instance status..."
    for i in {1..30}; do
        READY_COUNT=$(kubectl get alloys -n monitoring -o json 2>/dev/null | jq -r '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo "0")
        TOTAL_COUNT=$(kubectl get alloys -n monitoring --no-headers 2>/dev/null | wc -l)

        if [ "$READY_COUNT" -ge 3 ] && [ "$TOTAL_COUNT" -ge 3 ]; then
            log_info "All Alloy instances are ready!"
            break
        fi

        if [ $i -eq 30 ]; then
            log_warn "Timeout waiting for all Alloy instances, but continuing..."
            kubectl get alloys -n monitoring 2>/dev/null || true
        fi

        sleep 2
    done

    log_info "Grafana Alloy deployed successfully!"
}

# Deploy Standalone Monitoring (Self-monitoring for observability stack)
deploy_standalone_monitoring() {
    log_step "Step 7: Deploying Standalone Monitoring"

    log_info "Deploying custom Alloy collectors for observability stack self-monitoring..."

    # Deploy Prometheus self-monitoring
    log_info "Deploying Prometheus self-monitoring..."
    kubectl apply -f "${INFRA_DIR}/prometheus-standalone-monitoring.yaml"

    # Deploy Loki self-monitoring
    log_info "Deploying Loki self-monitoring..."
    kubectl apply -f "${INFRA_DIR}/loki-standalone-monitoring.yaml"

    # Deploy Grafana self-monitoring
    log_info "Deploying Grafana self-monitoring..."
    kubectl apply -f "${INFRA_DIR}/grafana-standalone-monitoring.yaml"

    # Wait for standalone Alloy instances to be ready
    sleep 5
    log_info "Waiting for standalone monitoring instances to be ready..."

    for i in {1..20}; do
        STANDALONE_READY=$(kubectl get alloys -n monitoring -o json 2>/dev/null | jq -r '[.items[] | select(.metadata.name | test("prometheus-observability|loki-exporter|grafana-exporter")) | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo "0")

        if [ "$STANDALONE_READY" -ge 3 ]; then
            log_info "All standalone monitoring instances are ready!"
            break
        fi

        if [ $i -eq 20 ]; then
            log_info "Standalone monitoring instances deployed (some may still be initializing)"
            kubectl get alloys -n monitoring | grep -E "(prometheus-observability|loki-exporter|grafana-exporter)" || true
        fi

        sleep 3
    done

    log_info "Standalone monitoring deployed successfully!"
    log_info "Your observability stack is now monitoring itself!"
}

# Verify deployment
verify_deployment() {
    log_step "Step 8: Verifying deployment"

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

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Observability Stack Deployed Successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    echo -e "${BLUE}📊 Stack Components:${NC}"
    echo -e "  ✓ Prometheus  - Metrics storage & querying"
    echo -e "  ✓ Loki        - Log aggregation & storage"
    echo -e "  ✓ Grafana     - Visualization & dashboards"
    echo -e "  ✓ Alloy       - Metrics & log collection"
    echo -e "  ✓ Self-Mon    - Observability stack self-monitoring\n"

    echo -e "${BLUE}🌐 Access Information:${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━\n"

    echo -e "${GREEN}Grafana Dashboard:${NC}"
    echo -e "  Command:      ${YELLOW}make grafana-dashboard${NC}"
    echo -e "  URL:          ${YELLOW}http://localhost:3000${NC}"
    echo -e "  Credentials:  ${YELLOW}admin / admin${NC}\n"

    echo -e "${GREEN}Prometheus UI:${NC}"
    echo -e "  Command:      ${YELLOW}make prometheus-ui${NC}"
    echo -e "  URL:          ${YELLOW}http://localhost:9090${NC}\n"

    echo -e "${BLUE}🔍 Monitoring Stack Self-Monitoring:${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    echo -e "  The observability stack is now monitoring itself!"
    echo -e "  Check Grafana for metrics from:"
    echo -e "    • Prometheus (job: integrations/unix)"
    echo -e "    • Loki (job: integrations/unix)"
    echo -e "    • Grafana (job: integrations/unix)\n"

    echo -e "${BLUE}⚡ Quick Commands:${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━\n"
    echo -e "  View all components:  ${YELLOW}make monitoring-status${NC}"
    echo -e "  View Prometheus logs: ${YELLOW}make logs-prometheus${NC}"
    echo -e "  View Loki logs:       ${YELLOW}make logs-loki${NC}"
    echo -e "  View Alloy logs:      ${YELLOW}make logs-alloy${NC}"
    echo -e "  Destroy stack:        ${YELLOW}make destroy-observability${NC}\n"

    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo -e "━━━━━━━━━━━━━━\n"
    echo -e "  1. Open Grafana:       ${YELLOW}make grafana-dashboard${NC}"
    echo -e "  2. Explore dashboards: Check pre-configured datasources"
    echo -e "  3. View self-metrics:  Search for 'integrations/unix' job"
    echo -e "  4. Deploy your app:    Add Prometheus scrape annotations\n"
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
    deploy_standalone_monitoring
    verify_deployment
    show_access_info
}

# Run main function
main
