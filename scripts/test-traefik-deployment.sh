#!/bin/bash
set -e

# Traefik Deployment Test Script
# Tests the complete Traefik deployment workflow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Traefik Deployment Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Deploy infrastructure if not running
deploy_infrastructure() {
    echo -e "${GREEN}[TEST 1/7]${NC} Checking Talos cluster status..."

    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${YELLOW}[INFO]${NC} Cluster not running. Deploying Talos infrastructure..."
        cd "${PROJECT_ROOT}"
        make deploy-infra
        sleep 10
    else
        echo -e "${GREEN}[INFO]${NC} Cluster is already running"
    fi

    # Verify cluster is healthy
    kubectl get nodes
    echo ""
}

# Step 2: Deploy observability stack if not present
deploy_observability() {
    echo -e "${GREEN}[TEST 2/7]${NC} Checking observability stack..."

    if ! kubectl get namespace monitoring &> /dev/null; then
        echo -e "${YELLOW}[INFO]${NC} Monitoring namespace not found. Deploying observability stack..."
        cd "${PROJECT_ROOT}"
        make deploy-observability
        sleep 10
    else
        echo -e "${GREEN}[INFO]${NC} Observability stack is already deployed"
    fi

    # Verify monitoring namespace
    kubectl get pods -n monitoring
    echo ""
}

# Step 3: Deploy Traefik
deploy_traefik() {
    echo -e "${GREEN}[TEST 3/7]${NC} Deploying Traefik ingress controller..."

    cd "${PROJECT_ROOT}"
    make deploy-traefik

    echo ""
}

# Step 4: Verify Traefik pods
verify_traefik_pods() {
    echo -e "${GREEN}[TEST 4/7]${NC} Verifying Traefik pods..."

    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if kubectl get pods -n traefik -l app.kubernetes.io/name=traefik | grep -q "Running"; then
            echo -e "${GREEN}[SUCCESS]${NC} Traefik pods are running"
            kubectl get pods -n traefik
            return 0
        fi

        attempt=$((attempt + 1))
        echo -e "${YELLOW}[INFO]${NC} Waiting for Traefik pods... (attempt $attempt/$max_attempts)"
        sleep 5
    done

    echo -e "${RED}[ERROR]${NC} Traefik pods did not start within timeout"
    return 1
}

# Step 5: Verify IngressRoutes
verify_ingressroutes() {
    echo ""
    echo -e "${GREEN}[TEST 5/7]${NC} Verifying IngressRoutes..."

    local routes=$(kubectl get ingressroute -A --no-headers | wc -l)

    if [ "$routes" -eq 0 ]; then
        echo -e "${RED}[ERROR]${NC} No IngressRoutes found"
        return 1
    fi

    echo -e "${GREEN}[SUCCESS]${NC} Found $routes IngressRoute(s)"
    kubectl get ingressroute -A
    echo ""
}

# Step 6: Verify DNS configuration
verify_dns() {
    echo -e "${GREEN}[TEST 6/7]${NC} Verifying DNS configuration..."

    if grep -q "grafana.local.dev" /etc/hosts; then
        echo -e "${GREEN}[SUCCESS]${NC} DNS entries found in /etc/hosts"
        grep "local.dev" /etc/hosts
    else
        echo -e "${RED}[ERROR]${NC} DNS entries not found in /etc/hosts"
        return 1
    fi
    echo ""
}

# Step 7: Test endpoint accessibility
test_endpoints() {
    echo -e "${GREEN}[TEST 7/7]${NC} Testing endpoint accessibility..."
    echo ""

    # Wait for services to be fully ready
    echo -e "${YELLOW}[INFO]${NC} Waiting 15 seconds for services to stabilize..."
    sleep 15

    local success_count=0
    local total_tests=0

    # Test Traefik dashboard
    echo -n "Testing http://traefik.local.dev ... "
    total_tests=$((total_tests + 1))
    if curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://traefik.local.dev | grep -q "200"; then
        echo -e "${GREEN}✓ OK${NC}"
        success_count=$((success_count + 1))
    else
        echo -e "${YELLOW}✗ Failed${NC}"
    fi

    # Test Grafana
    if kubectl get svc -n monitoring grafana &> /dev/null; then
        echo -n "Testing http://grafana.local.dev ... "
        total_tests=$((total_tests + 1))
        if curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://grafana.local.dev | grep -q "200"; then
            echo -e "${GREEN}✓ OK${NC}"
            success_count=$((success_count + 1))
        else
            echo -e "${YELLOW}✗ Failed${NC}"
        fi
    fi

    # Test Prometheus
    if kubectl get svc -n monitoring prometheus &> /dev/null; then
        echo -n "Testing http://prometheus.local.dev ... "
        total_tests=$((total_tests + 1))
        if curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://prometheus.local.dev | grep -q "200"; then
            echo -e "${GREEN}✓ OK${NC}"
            success_count=$((success_count + 1))
        else
            echo -e "${YELLOW}✗ Failed${NC}"
        fi
    fi

    echo ""
    echo -e "${BLUE}[RESULT]${NC} Passed $success_count/$total_tests endpoint tests"

    if [ $success_count -eq $total_tests ]; then
        return 0
    else
        return 1
    fi
}

# Show summary
show_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Test Summary${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    echo -e "${BLUE}[INFO]${NC} Deployment Status:"
    echo ""
    echo "Traefik Pods:"
    kubectl get pods -n traefik
    echo ""
    echo "IngressRoutes:"
    kubectl get ingressroute -A
    echo ""

    echo -e "${BLUE}[INFO]${NC} Access URLs:"
    echo "  - Traefik Dashboard: http://traefik.local.dev"
    echo "  - Grafana: http://grafana.local.dev (admin/admin)"
    echo "  - Prometheus: http://prometheus.local.dev"
    echo ""

    echo -e "${BLUE}[INFO]${NC} Useful Commands:"
    echo "  make endpoints         - Show all available endpoints"
    echo "  make test-endpoints    - Test endpoint accessibility"
    echo "  make logs-traefik      - View Traefik logs"
    echo "  make traefik-status    - Show Traefik status"
    echo "  make destroy-traefik   - Remove Traefik"
    echo ""
}

# Main test execution
main() {
    local test_failed=false

    deploy_infrastructure || test_failed=true
    deploy_observability || test_failed=true
    deploy_traefik || test_failed=true
    verify_traefik_pods || test_failed=true
    verify_ingressroutes || test_failed=true
    verify_dns || test_failed=true
    test_endpoints || test_failed=true

    show_summary

    if [ "$test_failed" = true ]; then
        echo -e "${YELLOW}[WARN]${NC} Some tests failed, but deployment may still be functional"
        echo -e "${YELLOW}[HINT]${NC} Check the output above for details"
        return 1
    else
        echo -e "${GREEN}[SUCCESS]${NC} All tests passed! Traefik is fully operational."
        return 0
    fi
}

# Run main function
main

exit $?
