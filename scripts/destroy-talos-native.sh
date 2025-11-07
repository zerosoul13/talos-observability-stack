#!/bin/bash

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CLUSTER_NAME="talos-local"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

main() {
    log_info "Destroying Talos cluster: ${CLUSTER_NAME}..."

    if ! talosctl cluster show --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
        log_warn "Cluster '${CLUSTER_NAME}' does not exist"
        exit 0
    fi

    # talosctl handles EVERYTHING - removes containers, networks, volumes
    talosctl cluster destroy --name "${CLUSTER_NAME}"

    log_info "Cluster destroyed successfully!"
}

main "$@"
