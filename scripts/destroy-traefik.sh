#!/bin/bash
set -e

# Traefik Destruction Script
# Removes Traefik ingress controller and optionally cleans DNS entries

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infrastructure/traefik"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
CLEAN_DNS=false
KEEP_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean-dns)
            CLEAN_DNS=true
            shift
            ;;
        --keep-config)
            KEEP_CONFIG=true
            shift
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Usage: $0 [--clean-dns] [--keep-config]"
            echo "  --clean-dns    Remove DNS entries from /etc/hosts"
            echo "  --keep-config  Keep configuration files in ${INFRA_DIR}"
            exit 1
            ;;
    esac
done

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Traefik Ingress Destruction${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Check cluster connectivity
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${YELLOW}[WARN]${NC} Cannot connect to Kubernetes cluster"
        echo -e "${YELLOW}[INFO]${NC} Skipping Kubernetes resource cleanup"
        return 1
    fi
    return 0
}

# Delete IngressRoutes
delete_ingressroutes() {
    echo -e "${GREEN}[1/3]${NC} Deleting IngressRoute configurations..."

    # Delete Traefik dashboard IngressRoute
    if kubectl get ingressroute -n traefik traefik-dashboard &> /dev/null; then
        echo -e "${GREEN}[INFO]${NC} Deleting Traefik dashboard IngressRoute..."
        kubectl delete -f "${INFRA_DIR}/traefik-dashboard-ingressroute.yaml" --ignore-not-found=true
    fi

    # Delete monitoring IngressRoutes if they exist
    if kubectl get namespace monitoring &> /dev/null; then
        if kubectl get ingressroute -n monitoring grafana &> /dev/null; then
            echo -e "${GREEN}[INFO]${NC} Deleting Grafana IngressRoute..."
            kubectl delete -f "${INFRA_DIR}/grafana-ingressroute.yaml" --ignore-not-found=true
        fi

        if kubectl get ingressroute -n monitoring prometheus &> /dev/null; then
            echo -e "${GREEN}[INFO]${NC} Deleting Prometheus IngressRoute..."
            kubectl delete -f "${INFRA_DIR}/prometheus-ingressroute.yaml" --ignore-not-found=true
        fi
    fi

    echo -e "${GREEN}[SUCCESS]${NC} IngressRoutes deleted"
}

# Uninstall Traefik Helm release
uninstall_traefik() {
    echo ""
    echo -e "${GREEN}[2/3]${NC} Uninstalling Traefik Helm release..."

    if ! command -v helm &> /dev/null; then
        echo -e "${YELLOW}[WARN]${NC} Helm not found, skipping Helm uninstall"
        return
    fi

    if helm list -n traefik | grep -q traefik; then
        echo -e "${GREEN}[INFO]${NC} Uninstalling Traefik..."
        helm uninstall traefik -n traefik --wait --timeout 2m || true

        # Wait for pods to terminate
        echo -e "${GREEN}[INFO]${NC} Waiting for Traefik pods to terminate..."
        kubectl wait --for=delete pod \
            -l app.kubernetes.io/name=traefik \
            -n traefik \
            --timeout=120s || true

        echo -e "${GREEN}[SUCCESS]${NC} Traefik uninstalled"
    else
        echo -e "${YELLOW}[WARN]${NC} Traefik Helm release not found"
    fi

    # Delete namespace if empty
    if kubectl get namespace traefik &> /dev/null; then
        local pod_count=$(kubectl get pods -n traefik --no-headers 2>/dev/null | wc -l)
        if [ "$pod_count" -eq 0 ]; then
            echo -e "${GREEN}[INFO]${NC} Deleting Traefik namespace..."
            kubectl delete namespace traefik --wait --timeout=60s || true
        else
            echo -e "${YELLOW}[WARN]${NC} Traefik namespace still has pods, skipping deletion"
        fi
    fi
}

# Clean DNS entries
clean_dns_entries() {
    echo ""
    echo -e "${GREEN}[3/3]${NC} Cleaning DNS entries..."

    if [ "$CLEAN_DNS" = true ]; then
        chmod +x "${INFRA_DIR}/setup-dns.sh"

        # Check if already running as root
        if [ "$EUID" -eq 0 ]; then
            bash "${INFRA_DIR}/setup-dns.sh" --remove
        else
            echo -e "${YELLOW}[INFO]${NC} DNS cleanup requires sudo privileges"
            sudo bash "${INFRA_DIR}/setup-dns.sh" --remove
        fi

        echo -e "${GREEN}[SUCCESS]${NC} DNS entries removed"
    else
        echo -e "${YELLOW}[INFO]${NC} Skipping DNS cleanup (use --clean-dns to remove)"
    fi
}

# Show completion message
show_completion() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Traefik Destruction Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    if [ "$CLEAN_DNS" = false ]; then
        echo -e "${BLUE}[INFO]${NC} DNS entries in /etc/hosts were NOT removed"
        echo -e "${BLUE}[INFO]${NC} To remove them, run:"
        echo "  sudo bash ${INFRA_DIR}/setup-dns.sh --remove"
        echo "  OR"
        echo "  bash $0 --clean-dns"
        echo ""
    fi

    if [ "$KEEP_CONFIG" = true ]; then
        echo -e "${BLUE}[INFO]${NC} Configuration files kept in ${INFRA_DIR}"
        echo ""
    fi

    echo -e "${BLUE}[INFO]${NC} Traefik has been removed from the cluster"
    echo ""
}

# Main execution
main() {
    if check_cluster; then
        delete_ingressroutes
        uninstall_traefik
    fi

    clean_dns_entries
    show_completion
}

# Confirmation prompt
echo -e "${YELLOW}[WARN]${NC} This will remove Traefik and all IngressRoutes"
if [ "$CLEAN_DNS" = true ]; then
    echo -e "${YELLOW}[WARN]${NC} DNS entries will also be removed from /etc/hosts"
fi
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    main
else
    echo -e "${BLUE}[INFO]${NC} Destruction cancelled"
    exit 0
fi

exit 0
