#!/bin/bash
set -e

# Traefik Deployment Script
# Deploys Traefik ingress controller and configures IngressRoutes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infrastructure/traefik"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Traefik Ingress Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Step 1: Check cluster is running
check_cluster() {
    echo -e "${GREEN}[1/6]${NC} Checking cluster connectivity..."

    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} Cannot connect to Kubernetes cluster"
        echo -e "${YELLOW}[HINT]${NC} Please deploy the Talos cluster first: make deploy-infra"
        exit 1
    fi

    # Check if worker nodes are ready
    local ready_workers=$(kubectl get nodes --no-headers -l node-role.kubernetes.io/control-plane="" | grep -c " Ready " || true)

    if [ "$ready_workers" -eq 0 ]; then
        echo -e "${RED}[ERROR]${NC} No ready worker nodes found"
        echo -e "${YELLOW}[HINT]${NC} Traefik requires worker nodes to run"
        exit 1
    fi

    echo -e "${GREEN}[INFO]${NC} Cluster is ready with $ready_workers worker node(s)"
}

# Step 2: Install Traefik via Helm
install_traefik() {
    echo ""
    echo -e "${GREEN}[2/6]${NC} Installing Traefik via Helm..."

    chmod +x "${INFRA_DIR}/traefik-helm-install.sh"
    bash "${INFRA_DIR}/traefik-helm-install.sh"
}

# Step 3: Wait for Traefik to be ready
wait_for_traefik() {
    echo ""
    echo -e "${GREEN}[3/6]${NC} Waiting for Traefik pods to be ready..."

    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=traefik \
        -n traefik \
        --timeout=300s

    # Give Traefik a few seconds to start listening on ports
    sleep 5

    echo -e "${GREEN}[INFO]${NC} Traefik is ready!"
}

# Step 4: Apply IngressRoute configurations
apply_ingressroutes() {
    echo ""
    echo -e "${GREEN}[4/6]${NC} Applying IngressRoute configurations..."

    # Apply Traefik dashboard IngressRoute
    echo -e "${GREEN}[INFO]${NC} Applying Traefik dashboard IngressRoute..."
    kubectl apply -f "${INFRA_DIR}/traefik-dashboard-ingressroute.yaml"

    # Check if monitoring namespace exists (for Grafana and Prometheus)
    if kubectl get namespace monitoring &> /dev/null; then
        echo -e "${GREEN}[INFO]${NC} Applying Grafana IngressRoute..."
        kubectl apply -f "${INFRA_DIR}/grafana-ingressroute.yaml"

        echo -e "${GREEN}[INFO]${NC} Applying Prometheus IngressRoute..."
        kubectl apply -f "${INFRA_DIR}/prometheus-ingressroute.yaml"
    else
        echo -e "${YELLOW}[WARN]${NC} Monitoring namespace not found. Skipping Grafana and Prometheus IngressRoutes."
        echo -e "${YELLOW}[HINT]${NC} Deploy observability stack first: make deploy-observability"
    fi

    echo -e "${GREEN}[SUCCESS]${NC} IngressRoutes applied successfully!"
}

# Step 5: Setup DNS
setup_dns() {
    echo ""
    echo -e "${GREEN}[5/6]${NC} Setting up DNS configuration..."

    chmod +x "${INFRA_DIR}/setup-dns.sh"

    # Check if already running as root
    if [ "$EUID" -eq 0 ]; then
        bash "${INFRA_DIR}/setup-dns.sh"
    else
        echo -e "${YELLOW}[INFO]${NC} DNS setup requires sudo privileges"
        sudo bash "${INFRA_DIR}/setup-dns.sh"
    fi
}

# Step 6: Verify endpoints
verify_endpoints() {
    echo ""
    echo -e "${GREEN}[6/6]${NC} Verifying endpoint accessibility..."

    local endpoints=(
        "http://traefik.local.dev"
    )

    # Add monitoring endpoints if namespace exists
    if kubectl get namespace monitoring &> /dev/null; then
        # Check if services exist before adding to test list
        if kubectl get svc -n monitoring grafana &> /dev/null; then
            endpoints+=("http://grafana.local.dev")
        fi
        if kubectl get svc -n monitoring prometheus &> /dev/null; then
            endpoints+=("http://prometheus.local.dev")
        fi
    fi

    echo ""
    for endpoint in "${endpoints[@]}"; do
        echo -n "Testing $endpoint ... "
        if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$endpoint" &> /dev/null; then
            echo -e "${GREEN}✓ OK${NC}"
        else
            echo -e "${YELLOW}✗ Not responding (service may not be running yet)${NC}"
        fi
    done
}

# Display access information
show_access_info() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Traefik Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}[INFO]${NC} Access URLs:"
    echo ""
    echo "  Traefik Dashboard:"
    echo "    http://traefik.local.dev"
    echo ""

    if kubectl get namespace monitoring &> /dev/null; then
        if kubectl get svc -n monitoring grafana &> /dev/null; then
            echo "  Grafana:"
            echo "    http://grafana.local.dev"
            echo ""
        fi

        if kubectl get svc -n monitoring prometheus &> /dev/null; then
            echo "  Prometheus:"
            echo "    http://prometheus.local.dev"
            echo ""
        fi
    fi

    echo -e "${BLUE}[INFO]${NC} Traefik Status:"
    kubectl get pods -n traefik -l app.kubernetes.io/name=traefik
    echo ""

    if kubectl get ingressroute -A &> /dev/null; then
        echo -e "${BLUE}[INFO]${NC} Active IngressRoutes:"
        kubectl get ingressroute -A
        echo ""
    fi

    echo -e "${BLUE}[INFO]${NC} Useful commands:"
    echo "  View Traefik logs:    kubectl logs -n traefik -l app.kubernetes.io/name=traefik -f"
    echo "  List IngressRoutes:   kubectl get ingressroute -A"
    echo "  Check DNS:            cat /etc/hosts | grep local.dev"
    echo "  Test endpoint:        curl -v http://traefik.local.dev"
    echo ""
}

# Main execution
main() {
    check_cluster
    install_traefik
    wait_for_traefik
    apply_ingressroutes
    setup_dns
    verify_endpoints
    show_access_info
}

# Run main function
main

exit 0
