#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="talos-local"
NETWORK_NAME="talos-net"
CONTROL_PLANE_NAME="talos-cp-01"
WORKER_1_NAME="talos-worker-01"
WORKER_2_NAME="talos-worker-02"

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

log_section() {
    echo
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

check_docker_containers() {
    log_section "Docker Container Status"

    local containers=("${CONTROL_PLANE_NAME}" "${WORKER_1_NAME}" "${WORKER_2_NAME}")
    local running=0
    local stopped=0
    local missing=0

    for container in "${containers[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            echo -e "  ${GREEN}✓${NC} ${container} - Running"
            running=$((running + 1))
        elif docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            echo -e "  ${RED}✗${NC} ${container} - Stopped"
            stopped=$((stopped + 1))
        else
            echo -e "  ${RED}✗${NC} ${container} - Not Found"
            missing=$((missing + 1))
        fi
    done

    echo
    echo "Summary: ${running} running, ${stopped} stopped, ${missing} missing"

    if [ $running -eq 3 ]; then
        return 0
    else
        return 1
    fi
}

check_docker_network() {
    log_section "Docker Network Status"

    if docker network inspect "${NETWORK_NAME}" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Network ${NETWORK_NAME} exists"

        # Show network details
        echo
        echo "Network Details:"
        docker network inspect "${NETWORK_NAME}" --format '  Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}'
        docker network inspect "${NETWORK_NAME}" --format '  Gateway: {{range .IPAM.Config}}{{.Gateway}}{{end}}'

        echo
        echo "Connected Containers:"
        docker network inspect "${NETWORK_NAME}" --format '{{range $k, $v := .Containers}}  - {{$v.Name}} ({{$v.IPv4Address}}){{println}}{{end}}'

        return 0
    else
        echo -e "  ${RED}✗${NC} Network ${NETWORK_NAME} not found"
        return 1
    fi
}

check_talos_health() {
    log_section "Talos Nodes Health"

    if ! command -v talosctl &> /dev/null; then
        log_error "talosctl not installed"
        return 1
    fi

    local talosconfig="${HOME}/.talos/config"
    if [ ! -f "$talosconfig" ]; then
        log_error "Talosconfig not found at ${talosconfig}"
        return 1
    fi

    echo "Checking Talos API connectivity..."
    echo

    # Check control plane
    if talosctl --talosconfig "$talosconfig" --nodes 172.30.0.2 version &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Control Plane (172.30.0.2) - Talos API Reachable"

        # Get version info
        local version=$(talosctl --talosconfig "$talosconfig" --nodes 172.30.0.2 version --short 2>/dev/null | head -1)
        echo "    Version: ${version}"
    else
        echo -e "  ${RED}✗${NC} Control Plane (172.30.0.2) - Talos API Unreachable"
    fi

    # Check workers
    local workers=("172.30.0.3" "172.30.0.4")
    local worker_names=("${WORKER_1_NAME}" "${WORKER_2_NAME}")

    for i in "${!workers[@]}"; do
        local ip="${workers[$i]}"
        local name="${worker_names[$i]}"

        if talosctl --talosconfig "$talosconfig" --nodes "$ip" version &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} ${name} (${ip}) - Talos API Reachable"
        else
            echo -e "  ${RED}✗${NC} ${name} (${ip}) - Talos API Unreachable"
        fi
    done
}

check_kubernetes_cluster() {
    log_section "Kubernetes Cluster Status"

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not installed"
        return 1
    fi

    # Check if cluster is reachable
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        echo "  Make sure kubeconfig is configured correctly"
        return 1
    fi

    echo "Cluster Information:"
    kubectl cluster-info 2>/dev/null | head -2

    echo
    echo "Node Status:"
    kubectl get nodes

    echo
    echo "System Pods Status:"
    kubectl get pods -n kube-system

    echo
    echo "Storage Classes:"
    kubectl get storageclass

    echo
    echo "Namespaces:"
    kubectl get namespaces
}

check_resource_usage() {
    log_section "Resource Usage"

    echo "Docker Container Stats:"
    echo

    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" \
        "${CONTROL_PLANE_NAME}" "${WORKER_1_NAME}" "${WORKER_2_NAME}" 2>/dev/null || log_warn "Could not retrieve container stats"

    echo
    echo "Docker Volumes:"
    docker volume ls --filter "name=talos" --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"
}

check_exposed_ports() {
    log_section "Exposed Ports"

    echo "Port Bindings:"
    echo
    echo -e "  Kubernetes API:    https://127.0.0.1:6443"
    echo -e "  Talos API:         https://127.0.0.1:50000"
    echo -e "  HTTP:              http://127.0.0.1:80"
    echo -e "  HTTPS:             https://127.0.0.1:443"

    echo
    echo "Testing Port Connectivity:"

    # Test Kubernetes API
    if nc -z -w2 127.0.0.1 6443 &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Port 6443 (Kubernetes API) - Listening"
    else
        echo -e "  ${RED}✗${NC} Port 6443 (Kubernetes API) - Not Listening"
    fi

    # Test Talos API
    if nc -z -w2 127.0.0.1 50000 &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Port 50000 (Talos API) - Listening"
    else
        echo -e "  ${RED}✗${NC} Port 50000 (Talos API) - Not Listening"
    fi

    # Test HTTP
    if nc -z -w2 127.0.0.1 80 &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Port 80 (HTTP) - Listening"
    else
        echo -e "  ${YELLOW}⚠${NC} Port 80 (HTTP) - Not Listening (Normal if Traefik not deployed)"
    fi

    # Test HTTPS
    if nc -z -w2 127.0.0.1 443 &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Port 443 (HTTPS) - Listening"
    else
        echo -e "  ${YELLOW}⚠${NC} Port 443 (HTTPS) - Not Listening (Normal if Traefik not deployed)"
    fi
}

print_summary() {
    log_section "Summary"

    local issues=0

    # Check containers
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTROL_PLANE_NAME}$"; then
        issues=$((issues + 1))
    fi

    # Check kubectl
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Cluster is operational"
    else
        echo -e "  ${RED}✗${NC} Cluster is not operational"
        issues=$((issues + 1))
    fi

    echo
    if [ $issues -eq 0 ]; then
        log_info "All systems operational!"
        echo
        echo "Useful Commands:"
        echo "  kubectl get nodes"
        echo "  kubectl get pods -A"
        echo "  talosctl dashboard"
        echo "  talosctl health"
        echo "  make deploy-traefik    # Deploy ingress controller"
        echo "  make deploy-observability    # Deploy monitoring stack"
    else
        log_error "Cluster has ${issues} issues"
        echo
        echo "Troubleshooting:"
        echo "  1. Check Docker logs: docker logs ${CONTROL_PLANE_NAME}"
        echo "  2. Check Talos logs: talosctl --nodes 172.30.0.2 logs"
        echo "  3. Destroy and recreate: make destroy-infra && make deploy-infra"
    fi
}

main() {
    log_info "Checking Talos Kubernetes Cluster Status..."

    check_docker_containers
    check_docker_network
    check_talos_health
    check_kubernetes_cluster
    check_resource_usage
    check_exposed_ports
    print_summary

    echo
}

main "$@"
