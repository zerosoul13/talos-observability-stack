#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TALOS_VERSION="v1.8.3"
KUBERNETES_VERSION="1.31.1"
CLUSTER_NAME="talos-local"
NETWORK_NAME="talos-net"
CONTROL_PLANE_NAME="talos-cp-01"
WORKER_1_NAME="talos-worker-01"
WORKER_2_NAME="talos-worker-02"

# Ports
KUBERNETES_API_PORT=6444
TALOS_API_PORT_CP=50000
TALOS_API_PORT_W1=50001
TALOS_API_PORT_W2=50002
HTTP_PORT=80
HTTPS_PORT=443

# Resources
CPU_COUNT=2
MEMORY_MB=4096

# Directories
CONFIG_DIR="${PROJECT_ROOT}/infrastructure/talos"
KUBECONFIG_DIR="${HOME}/.kube"
TALOSCONFIG_DIR="${HOME}/.talos"

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

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
        return 1
    fi
    log_info "$1 is installed: $(command -v "$1")"
}

check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=0

    if ! check_command docker; then
        missing_deps=1
    fi

    if ! check_command talosctl; then
        missing_deps=1
    fi

    if ! check_command kubectl; then
        missing_deps=1
    fi

    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker daemon."
        missing_deps=1
    fi

    if [ $missing_deps -eq 1 ]; then
        log_error "Missing required dependencies. Please install them first."
        exit 1
    fi

    log_info "All dependencies satisfied"
}

create_docker_network() {
    log_info "Creating Docker network: ${NETWORK_NAME}..."

    if docker network inspect "${NETWORK_NAME}" &> /dev/null; then
        log_warn "Network ${NETWORK_NAME} already exists, skipping creation"
    else
        docker network create \
            --driver bridge \
            --subnet=172.30.0.0/24 \
            --gateway=172.30.0.1 \
            "${NETWORK_NAME}"
        log_info "Network ${NETWORK_NAME} created successfully"
    fi
}

generate_talos_configs() {
    log_info "Generating Talos machine configurations for Docker..."

    mkdir -p "${CONFIG_DIR}"
    cd "${CONFIG_DIR}"

    # Remove old configs to regenerate with correct port
    rm -f controlplane.yaml worker.yaml talosconfig

    # Generate configs with patches for Docker/container mode
    # Create patch files for better readability
    cat > /tmp/talos-cp-patch.yaml <<'EOF'
machine:
  install:
    disk: /dev/null
  kubelet:
    registerWithFQDN: false
  features:
    rbac: true
EOF

    cat > /tmp/talos-worker-patch.yaml <<'EOF'
machine:
  install:
    disk: /dev/null
  kubelet:
    registerWithFQDN: false
EOF

    talosctl gen config \
        "${CLUSTER_NAME}" \
        "https://127.0.0.1:${KUBERNETES_API_PORT}" \
        --kubernetes-version "${KUBERNETES_VERSION}" \
        --output-types controlplane,worker,talosconfig \
        --config-patch-control-plane @/tmp/talos-cp-patch.yaml \
        --config-patch-worker @/tmp/talos-worker-patch.yaml \
        --force

    # Clean up temp files
    rm -f /tmp/talos-cp-patch.yaml /tmp/talos-worker-patch.yaml

    log_info "Generated Talos configurations with Docker-specific patches"

    # Copy talosconfig to home directory
    mkdir -p "${TALOSCONFIG_DIR}"
    cp -f talosconfig "${TALOSCONFIG_DIR}/config"

    log_info "Talos configuration saved to ${TALOSCONFIG_DIR}/config"
}

start_control_plane() {
    log_info "Starting control plane node: ${CONTROL_PLANE_NAME}..."

    # Create volume if it doesn't exist
    docker volume create talos-cp-01-data &> /dev/null || true

    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTROL_PLANE_NAME}$"; then
        log_warn "Control plane ${CONTROL_PLANE_NAME} already exists"

        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTROL_PLANE_NAME}$"; then
            log_info "Starting existing control plane container..."
            docker start "${CONTROL_PLANE_NAME}"
        fi
    else
        docker run -d \
            --name "${CONTROL_PLANE_NAME}" \
            --hostname "${CONTROL_PLANE_NAME}" \
            --network "${NETWORK_NAME}" \
            --ip 172.30.0.2 \
            --cpus="${CPU_COUNT}" \
            --memory="${MEMORY_MB}m" \
            --privileged \
            --restart=unless-stopped \
            -e PLATFORM=container \
            -v talos-cp-01-data:/var \
            -v /dev:/dev \
            -p ${KUBERNETES_API_PORT}:6443 \
            -p ${TALOS_API_PORT_CP}:50000 \
            "ghcr.io/siderolabs/talos:${TALOS_VERSION}"

        log_info "Control plane node started"
    fi

    # Wait for container to be running first
    log_info "Waiting for container to fully start..."
    sleep 10

    # Wait for Talos API port to be accessible
    # In maintenance mode, the API is limited, so we just check if port responds
    log_info "Waiting for Talos API port to be accessible..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if nc -z 127.0.0.1 ${TALOS_API_PORT_CP} 2>/dev/null; then
            log_info "Talos API port is accessible"
            break
        fi

        if [ $((retries % 5)) -eq 0 ]; then
            log_info "Still waiting for port ${TALOS_API_PORT_CP}... (${retries} attempts remaining)"
        fi

        retries=$((retries - 1))
        sleep 2
    done

    if [ $retries -eq 0 ]; then
        log_error "Talos API port did not become accessible"
        log_info "Checking if container is running..."
        docker ps --filter name="${CONTROL_PLANE_NAME}"
        log_info "Container logs:"
        docker logs "${CONTROL_PLANE_NAME}" --tail 50
        log_info "Port check:"
        nc -zv 127.0.0.1 ${TALOS_API_PORT_CP} 2>&1 || echo "Port ${TALOS_API_PORT_CP} not accessible"
        exit 1
    fi

    # Additional wait for API to stabilize
    log_info "Port is up, waiting for API to stabilize..."
    sleep 5

    # Configure talosctl endpoints - use localhost with mapped ports
    talosctl --talosconfig "${TALOSCONFIG_DIR}/config" config endpoint 127.0.0.1:${TALOS_API_PORT_CP}
    talosctl --talosconfig "${TALOSCONFIG_DIR}/config" config node 127.0.0.1

    log_info "Talosconfig updated with correct endpoints"
}

apply_control_plane_config() {
    log_info "Applying control plane configuration..."

    # Use --insecure mode and explicit nodes, don't rely on talosconfig endpoints yet
    talosctl apply-config \
        --nodes 127.0.0.1:${TALOS_API_PORT_CP} \
        --file "${CONFIG_DIR}/controlplane.yaml" \
        --insecure

    log_info "Control plane configuration applied, waiting for node to process it..."
    sleep 10
}

bootstrap_cluster() {
    log_info "Bootstrapping Kubernetes cluster..."

    # Wait a bit more for the node to process config and reboot
    log_info "Waiting for node to apply configuration (this can take 30-60 seconds)..."
    sleep 20

    # After config is applied, node will reboot and come up in configured mode
    # Wait for it to be accessible again
    log_info "Waiting for node to be accessible after configuration..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if nc -z 127.0.0.1 ${TALOS_API_PORT_CP} 2>/dev/null; then
            # Try to connect with talosctl (now should work with configured endpoints)
            if talosctl --talosconfig "${TALOSCONFIG_DIR}/config" \
                version &>/dev/null; then
                log_info "Node is accessible and responding"
                break
            fi
        fi
        retries=$((retries - 1))
        sleep 2
    done

    # Bootstrap the cluster
    log_info "Bootstrapping etcd..."
    talosctl --talosconfig "${TALOSCONFIG_DIR}/config" \
        bootstrap || log_warn "Cluster may already be bootstrapped"

    log_info "Kubernetes cluster bootstrap initiated"
}

start_worker_nodes() {
    log_info "Starting worker nodes..."

    # Create volumes
    docker volume create talos-worker-01-data &> /dev/null || true
    docker volume create talos-worker-02-data &> /dev/null || true

    # Worker 1 - Exposes HTTP/HTTPS for Traefik ingress
    if docker ps -a --format '{{.Names}}' | grep -q "^${WORKER_1_NAME}$"; then
        log_warn "Worker ${WORKER_1_NAME} already exists"
        if ! docker ps --format '{{.Names}}' | grep -q "^${WORKER_1_NAME}$"; then
            docker start "${WORKER_1_NAME}"
        fi
    else
        # Check if port 80 is already in use
        if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
            log_warn "Port 80 is already in use, worker 1 will not expose HTTP/HTTPS ports"
            log_warn "Traefik will need to use NodePort or you'll need to free port 80"
            docker run -d \
                --name "${WORKER_1_NAME}" \
                --hostname "${WORKER_1_NAME}" \
                --network "${NETWORK_NAME}" \
                --ip 172.30.0.3 \
                --cpus="${CPU_COUNT}" \
                --memory="${MEMORY_MB}m" \
                --privileged \
                --restart=unless-stopped \
                -e PLATFORM=container \
                -v talos-worker-01-data:/var \
                -v /dev:/dev \
                -p ${TALOS_API_PORT_W1}:50000 \
                "ghcr.io/siderolabs/talos:${TALOS_VERSION}"
        else
            docker run -d \
                --name "${WORKER_1_NAME}" \
                --hostname "${WORKER_1_NAME}" \
                --network "${NETWORK_NAME}" \
                --ip 172.30.0.3 \
                --cpus="${CPU_COUNT}" \
                --memory="${MEMORY_MB}m" \
                --privileged \
                --restart=unless-stopped \
                -e PLATFORM=container \
                -v talos-worker-01-data:/var \
                -v /dev:/dev \
                -p ${HTTP_PORT}:80 \
                -p ${HTTPS_PORT}:443 \
                -p ${TALOS_API_PORT_W1}:50000 \
                "ghcr.io/siderolabs/talos:${TALOS_VERSION}"
        fi

        log_info "Worker node ${WORKER_1_NAME} started"
    fi

    # Worker 2 - No HTTP/HTTPS ports (only one worker needs them)
    if docker ps -a --format '{{.Names}}' | grep -q "^${WORKER_2_NAME}$"; then
        log_warn "Worker ${WORKER_2_NAME} already exists"
        if ! docker ps --format '{{.Names}}' | grep -q "^${WORKER_2_NAME}$"; then
            docker start "${WORKER_2_NAME}"
        fi
    else
        docker run -d \
            --name "${WORKER_2_NAME}" \
            --hostname "${WORKER_2_NAME}" \
            --network "${NETWORK_NAME}" \
            --ip 172.30.0.4 \
            --cpus="${CPU_COUNT}" \
            --memory="${MEMORY_MB}m" \
            --privileged \
            --restart=unless-stopped \
            -e PLATFORM=container \
            -v talos-worker-02-data:/var \
            -v /dev:/dev \
            -p ${TALOS_API_PORT_W2}:50000 \
            "ghcr.io/siderolabs/talos:${TALOS_VERSION}"

        log_info "Worker node ${WORKER_2_NAME} started"
    fi

    sleep 5
}

apply_worker_configs() {
    log_info "Applying worker configurations..."

    # Wait for workers to be reachable
    log_info "Waiting for worker nodes Talos API to be ready..."
    sleep 10

    # Apply worker 1 config
    log_info "Applying config to worker 1..."
    local retries=15
    while [ $retries -gt 0 ]; do
        if talosctl --talosconfig "${TALOSCONFIG_DIR}/config" \
            apply-config \
            --nodes 127.0.0.1:${TALOS_API_PORT_W1} \
            --file "${CONFIG_DIR}/worker.yaml" \
            --insecure 2>/dev/null; then
            log_info "Worker 1 config applied successfully"
            break
        fi
        retries=$((retries - 1))
        sleep 2
    done

    # Apply worker 2 config
    log_info "Applying config to worker 2..."
    retries=15
    while [ $retries -gt 0 ]; do
        if talosctl --talosconfig "${TALOSCONFIG_DIR}/config" \
            apply-config \
            --nodes 127.0.0.1:${TALOS_API_PORT_W2} \
            --file "${CONFIG_DIR}/worker.yaml" \
            --insecure 2>/dev/null; then
            log_info "Worker 2 config applied successfully"
            break
        fi
        retries=$((retries - 1))
        sleep 2
    done

    log_info "Worker configurations applied"
}

generate_kubeconfig() {
    log_info "Generating kubeconfig..."

    mkdir -p "${KUBECONFIG_DIR}"

    # Wait for Kubernetes API to be ready
    log_info "Waiting for Kubernetes API to be ready..."
    local retries=60
    while [ $retries -gt 0 ]; do
        if talosctl --talosconfig "${TALOSCONFIG_DIR}/config" \
            kubeconfig --force &> /dev/null; then
            log_info "Kubeconfig generated successfully"
            break
        fi
        retries=$((retries - 1))
        sleep 5
    done

    if [ $retries -eq 0 ]; then
        log_error "Could not generate kubeconfig - API not ready"
        exit 1
    fi

    # Merge kubeconfig
    export KUBECONFIG="${KUBECONFIG_DIR}/config"
    log_info "Kubeconfig saved to ${KUBECONFIG_DIR}/config"
}

wait_for_nodes() {
    log_info "Waiting for all nodes to be Ready..."

    local retries=60
    while [ $retries -gt 0 ]; do
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")

        if [ "$ready_nodes" -eq 3 ]; then
            log_info "All 3 nodes are Ready"
            kubectl get nodes
            break
        fi

        log_info "Nodes ready: ${ready_nodes}/3 - waiting..."
        retries=$((retries - 1))
        sleep 5
    done

    if [ $retries -eq 0 ]; then
        log_error "Nodes did not become ready in time"
        kubectl get nodes
        exit 1
    fi
}

install_local_path_provisioner() {
    log_info "Installing local-path-provisioner for persistent storage..."

    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml

    # Wait for provisioner to be ready
    log_info "Waiting for local-path-provisioner to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=local-path-provisioner \
        -n local-path-storage \
        --timeout=120s || log_warn "Provisioner may still be starting"

    # Set as default storage class
    kubectl patch storageclass local-path \
        -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

    log_info "Local-path-provisioner installed and set as default storage class"
}

print_summary() {
    log_info "================================================================"
    log_info "Talos Kubernetes Cluster Deployment Complete!"
    log_info "================================================================"
    echo
    log_info "Cluster Information:"
    echo "  Cluster Name:        ${CLUSTER_NAME}"
    echo "  Kubernetes Version:  ${KUBERNETES_VERSION}"
    echo "  Talos Version:       ${TALOS_VERSION}"
    echo
    log_info "Node Information:"
    echo "  Control Plane:       ${CONTROL_PLANE_NAME} (172.30.0.2)"
    echo "  Worker 1:            ${WORKER_1_NAME} (172.30.0.3)"
    echo "  Worker 2:            ${WORKER_2_NAME} (172.30.0.4)"
    echo
    log_info "Exposed Ports:"
    echo "  Kubernetes API:         https://127.0.0.1:${KUBERNETES_API_PORT}"
    echo "  Talos API (CP):         https://127.0.0.1:${TALOS_API_PORT_CP}"
    echo "  Talos API (Worker 1):   https://127.0.0.1:${TALOS_API_PORT_W1}"
    echo "  Talos API (Worker 2):   https://127.0.0.1:${TALOS_API_PORT_W2}"
    echo "  HTTP (Traefik):         http://127.0.0.1:${HTTP_PORT}"
    echo "  HTTPS (Traefik):        https://127.0.0.1:${HTTPS_PORT}"
    echo
    log_info "Configuration Files:"
    echo "  Kubeconfig:          ${KUBECONFIG_DIR}/config"
    echo "  Talosconfig:         ${TALOSCONFIG_DIR}/config"
    echo "  Talos configs:       ${CONFIG_DIR}/"
    echo
    log_info "Useful Commands:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    echo "  talosctl dashboard"
    echo "  talosctl health"
    echo
    log_info "Next Steps:"
    echo "  1. Deploy Traefik ingress:      make deploy-traefik"
    echo "  2. Deploy observability stack:  make deploy-observability"
    echo "  3. Deploy sample application:   make deploy-sample-app"
    echo
    log_info "================================================================"
}

main() {
    log_info "Starting Talos Kubernetes cluster deployment..."
    echo

    check_dependencies
    create_docker_network
    generate_talos_configs
    start_control_plane
    apply_control_plane_config
    bootstrap_cluster
    start_worker_nodes
    apply_worker_configs
    generate_kubeconfig
    wait_for_nodes
    install_local_path_provisioner

    echo
    print_summary
}

main "$@"
