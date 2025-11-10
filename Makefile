.PHONY: help check-deps deploy-infra destroy-infra status kubeconfig clean deploy-observability destroy-observability

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "Talos Local Observability Platform - Makefile"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make check-deps           - Verify all dependencies"
	@echo "  2. make deploy-infra         - Deploy Talos cluster"
	@echo "  3. make deploy-observability - Deploy monitoring stack"
	@echo "  4. make grafana-dashboard    - Access Grafana dashboard"
	@echo ""

check-deps: ## Check if all required dependencies are installed
	@echo "$(GREEN)[INFO]$(NC) Checking dependencies..."
	@command -v docker >/dev/null 2>&1 || { echo "$(YELLOW)[ERROR]$(NC) docker not found. Please install Docker."; exit 1; }
	@echo "  ✓ docker: $$(docker --version)"
	@command -v kubectl >/dev/null 2>&1 || { echo "$(YELLOW)[ERROR]$(NC) kubectl not found. Please install kubectl."; exit 1; }
	@echo "  ✓ kubectl: $$(kubectl version --client --short 2>/dev/null || kubectl version --client)"
	@command -v talosctl >/dev/null 2>&1 || { echo "$(YELLOW)[ERROR]$(NC) talosctl not found. Please install talosctl."; exit 1; }
	@echo "  ✓ talosctl: $$(talosctl version --short --client)"
	@docker info >/dev/null 2>&1 || { echo "$(YELLOW)[ERROR]$(NC) Docker daemon is not running. Please start Docker."; exit 1; }
	@echo "  ✓ Docker daemon is running"
	@echo "$(GREEN)[INFO]$(NC) All dependencies satisfied!"

deploy-infra: check-deps ## Deploy the Talos Kubernetes cluster
	@echo "$(GREEN)[INFO]$(NC) Deploying Talos infrastructure..."
	@chmod +x scripts/deploy-talos-native.sh
	@./scripts/deploy-talos-native.sh

destroy-infra: ## Destroy the Talos cluster
	@chmod +x scripts/destroy-talos-native.sh
	@./scripts/destroy-talos-native.sh

status: ## Show cluster status and health information
	@chmod +x scripts/status-talos.sh
	@./scripts/status-talos.sh

kubeconfig: ## Export/update kubeconfig for the cluster
	@echo "$(GREEN)[INFO]$(NC) Exporting kubeconfig..."
	@talosctl --context talos-local kubeconfig --force
	@echo "$(GREEN)[INFO]$(NC) Kubeconfig updated at $(HOME)/.kube/config"
	@echo "$(GREEN)[INFO]$(NC) Current context: $$(kubectl config current-context)"

health: ## Check cluster health
	@echo "$(GREEN)[INFO]$(NC) Checking cluster health..."
	@kubectl get nodes -o wide
	@echo ""
	@echo "$(GREEN)[INFO]$(NC) System Pods:"
	@kubectl get pods -n kube-system --field-selector=status.phase!=Running 2>/dev/null || echo "  All system pods running"

cluster-info: ## Show comprehensive cluster information
	@echo "$(GREEN)[INFO]$(NC) Cluster Information"
	@echo ""
	@echo "Kubernetes Nodes:"
	@kubectl get nodes -o wide
	@echo ""
	@echo "System Pods:"
	@kubectl get pods -n kube-system
	@echo ""
	@echo "Cluster Version:"
	@kubectl version --short 2>/dev/null || kubectl version

containers: ## Show Talos cluster containers
	@docker ps --filter name=talos-local --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

nodes: ## List all Kubernetes nodes
	@kubectl get nodes -o wide

pods: ## List all pods in all namespaces
	@kubectl get pods -A -o wide

services: ## List all services in all namespaces
	@kubectl get svc -A

events: ## Show recent cluster events
	@kubectl get events -A --sort-by='.lastTimestamp' | tail -20

restart: destroy-infra deploy-infra ## Destroy and recreate the cluster

##
## Observability Stack Targets
##

deploy-observability: ## Deploy the complete observability stack (Prometheus, Loki, Grafana, Alloy)
	@echo "$(GREEN)[INFO]$(NC) Deploying observability stack..."
	@chmod +x scripts/deploy-observability.sh
	@./scripts/deploy-observability.sh

destroy-observability: ## Destroy the observability stack
	@chmod +x scripts/destroy-observability.sh
	@./scripts/destroy-observability.sh $(filter-out $@,$(MAKECMDGOALS))

destroy-observability-keep-data: ## Destroy observability stack but keep PVCs (preserve data)
	@chmod +x scripts/destroy-observability.sh
	@./scripts/destroy-observability.sh --keep-data

grafana-dashboard: ## Port-forward to Grafana dashboard
	@echo "$(GREEN)[INFO]$(NC) Port-forwarding to Grafana on http://localhost:3000"
	@echo "$(GREEN)[INFO]$(NC) Credentials: admin / admin"
	@echo "$(GREEN)[INFO]$(NC) Press Ctrl+C to stop port-forwarding"
	@kubectl port-forward -n monitoring svc/grafana 3000:3000

prometheus-ui: ## Port-forward to Prometheus UI
	@echo "$(GREEN)[INFO]$(NC) Port-forwarding to Prometheus on http://localhost:9090"
	@echo "$(GREEN)[INFO]$(NC) Press Ctrl+C to stop port-forwarding"
	@kubectl port-forward -n monitoring svc/prometheus 9090:9090

logs-prometheus: ## Show Prometheus logs
	@kubectl logs -n monitoring -l app=prometheus -f

logs-loki: ## Show Loki logs
	@kubectl logs -n monitoring -l app=loki -f

logs-alloy: ## Show Grafana Alloy logs
	@kubectl logs -n monitoring -l app.kubernetes.io/name=alloy -f

monitoring-status: ## Show status of all monitoring components
	@echo "$(GREEN)[INFO]$(NC) Monitoring Stack Status"
	@echo ""
	@echo "Pods:"
	@kubectl get pods -n monitoring -o wide
	@echo ""
	@echo "Services:"
	@kubectl get svc -n monitoring
	@echo ""
	@echo "Alloy Custom Resources:"
	@kubectl get alloys -n monitoring

# Catch-all target for passing arguments to destroy-infra
%:
	@:
