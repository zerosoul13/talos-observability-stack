#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="talos-local"
NETWORK_NAME="talos-net"
CONTROL_PLANE_NAME="talos-cp-01"
WORKER_1_NAME="talos-worker-01"
WORKER_2_NAME="talos-worker-02"

# Directories
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/infrastructure/talos"
KUBECONFIG_DIR="${HOME}/.kube"
TALOSCONFIG_DIR="${HOME}/.talos"

# Parse arguments
KEEP_CONFIG=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-config)
            KEEP_CONFIG=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--keep-config]"
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

confirm_destruction() {
    echo
    log_warn "This will destroy the entire Talos Kubernetes cluster!"
    echo
    echo "The following will be removed:"
    echo "  - Control plane node: ${CONTROL_PLANE_NAME}"
    echo "  - Worker nodes: ${WORKER_1_NAME}, ${WORKER_2_NAME}"
    echo "  - Docker network: ${NETWORK_NAME}"
    echo "  - Docker volumes for all nodes"

    if [ "$KEEP_CONFIG" = false ]; then
        echo "  - Configuration files in ${CONFIG_DIR}"
        echo "  - Kubeconfig context for ${CLUSTER_NAME}"
    else
        log_info "Configuration files will be preserved (--keep-config flag)"
    fi

    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled"
        exit 0
    fi
}

stop_and_remove_containers() {
    log_info "Stopping and removing Talos containers..."

    local containers=("${CONTROL_PLANE_NAME}" "${WORKER_1_NAME}" "${WORKER_2_NAME}")

    for container in "${containers[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            log_info "Stopping container: ${container}"
            docker stop "${container}" &> /dev/null || true

            log_info "Removing container: ${container}"
            docker rm -f "${container}" &> /dev/null || true
        else
            log_warn "Container ${container} does not exist, skipping"
        fi
    done

    log_info "All containers removed"
}

remove_docker_volumes() {
    log_info "Removing Docker volumes..."

    local volumes=(
        "talos-cp-01-data"
        "talos-worker-01-data"
        "talos-worker-02-data"
    )

    for volume in "${volumes[@]}"; do
        if docker volume ls --format '{{.Name}}' | grep -q "^${volume}$"; then
            log_info "Removing volume: ${volume}"
            docker volume rm -f "${volume}" &> /dev/null || log_warn "Could not remove volume ${volume}"
        fi
    done

    log_info "Volumes cleaned up"
}

remove_docker_network() {
    log_info "Removing Docker network: ${NETWORK_NAME}..."

    if docker network inspect "${NETWORK_NAME}" &> /dev/null; then
        docker network rm "${NETWORK_NAME}" || log_warn "Could not remove network ${NETWORK_NAME}"
        log_info "Network removed"
    else
        log_warn "Network ${NETWORK_NAME} does not exist, skipping"
    fi
}

cleanup_configs() {
    if [ "$KEEP_CONFIG" = true ]; then
        log_info "Keeping configuration files as requested"
        return
    fi

    log_info "Cleaning up configuration files..."

    # Remove Talos configs
    if [ -d "${CONFIG_DIR}" ]; then
        log_info "Removing Talos configurations from ${CONFIG_DIR}"
        rm -f "${CONFIG_DIR}/controlplane.yaml"
        rm -f "${CONFIG_DIR}/worker.yaml"
        rm -f "${CONFIG_DIR}/talosconfig"
    fi

    # Remove talosconfig from home directory
    if [ -f "${TALOSCONFIG_DIR}/config" ]; then
        log_info "Removing talosconfig from ${TALOSCONFIG_DIR}"
        rm -f "${TALOSCONFIG_DIR}/config"
    fi

    # Remove kubeconfig context
    if command -v kubectl &> /dev/null; then
        log_info "Removing kubectl context for ${CLUSTER_NAME}"
        kubectl config delete-context "admin@${CLUSTER_NAME}" &> /dev/null || log_warn "Context not found"
        kubectl config delete-cluster "${CLUSTER_NAME}" &> /dev/null || log_warn "Cluster not found"
        kubectl config delete-user "admin@${CLUSTER_NAME}" &> /dev/null || log_warn "User not found"
    fi

    log_info "Configuration cleanup complete"
}

verify_cleanup() {
    log_info "Verifying cleanup..."

    local issues=0

    # Check for remaining containers
    for container in "${CONTROL_PLANE_NAME}" "${WORKER_1_NAME}" "${WORKER_2_NAME}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            log_error "Container ${container} still exists"
            issues=$((issues + 1))
        fi
    done

    # Check for remaining network
    if docker network inspect "${NETWORK_NAME}" &> /dev/null; then
        log_error "Network ${NETWORK_NAME} still exists"
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        log_info "Cleanup verification passed"
    else
        log_warn "Some cleanup issues detected (${issues} total)"
        log_warn "You may need to manually remove remaining resources"
    fi
}

print_summary() {
    log_info "================================================================"
    log_info "Talos Cluster Destruction Complete"
    log_info "================================================================"
    echo
    log_info "Removed:"
    echo "  - Talos containers (control plane + workers)"
    echo "  - Docker network: ${NETWORK_NAME}"
    echo "  - Docker volumes"

    if [ "$KEEP_CONFIG" = false ]; then
        echo "  - Configuration files"
        echo "  - Kubeconfig context"
        echo
        log_info "Configuration files were removed"
        log_info "Run 'make deploy-infra' to create a new cluster"
    else
        echo
        log_info "Configuration files were preserved"
        log_info "Run 'make deploy-infra' to recreate the cluster with existing configs"
    fi

    echo
    log_info "================================================================"
}

main() {
    log_info "Starting Talos cluster destruction..."

    confirm_destruction
    stop_and_remove_containers
    remove_docker_volumes
    remove_docker_network
    cleanup_configs
    verify_cleanup

    echo
    print_summary
}

main "$@"
