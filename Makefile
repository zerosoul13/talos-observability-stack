.PHONY: help check-deps deploy-infra destroy-infra status kubeconfig clean deploy-observability destroy-observability deploy-traefik destroy-traefik endpoints setup-dns test-endpoints

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
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make check-deps       - Verify all dependencies"
	@echo "  2. make deploy-infra     - Deploy Talos cluster"
	@echo "  3. make status           - Check cluster status"
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

deploy-infra: check-deps ## Deploy the Talos Kubernetes cluster (native talosctl)
	@echo "$(GREEN)[INFO]$(NC) Deploying Talos infrastructure..."
	@chmod +x scripts/deploy-talos-native.sh
	@./scripts/deploy-talos-native.sh

deploy-infra-manual: check-deps ## Deploy using manual Docker approach (advanced, may have issues)
	@echo "$(YELLOW)[WARN]$(NC) Using manual Docker approach - may encounter sharedFilesystems errors"
	@echo "$(YELLOW)[WARN]$(NC) Recommended: use 'make deploy-infra' instead"
	@chmod +x scripts/deploy-talos.sh
	@./scripts/deploy-talos.sh

destroy-infra: ## Destroy the Talos cluster
	@chmod +x scripts/destroy-talos-native.sh
	@./scripts/destroy-talos-native.sh

destroy-infra-manual: ## Destroy manually deployed cluster
	@chmod +x scripts/destroy-talos.sh
	@./scripts/destroy-talos.sh

status: ## Show cluster status and health information
	@chmod +x scripts/status-talos.sh
	@./scripts/status-talos.sh

kubeconfig: ## Export/update kubeconfig for the cluster
	@echo "$(GREEN)[INFO]$(NC) Exporting kubeconfig..."
	@talosctl --context talos-local kubeconfig --force
	@echo "$(GREEN)[INFO]$(NC) Kubeconfig updated at $(HOME)/.kube/config"
	@echo "$(GREEN)[INFO]$(NC) Current context: $$(kubectl config current-context)"

dashboard: ## Open Talos dashboard for the cluster (Note: may not work with native deployment)
	@echo "$(YELLOW)[WARN]$(NC) Talos dashboard may not be available with native deployment"
	@echo "$(GREEN)[INFO]$(NC) Use 'kubectl' commands or 'make monitoring-status' instead"
	@talosctl --context talos-local dashboard 2>/dev/null || echo "$(YELLOW)[INFO]$(NC) Dashboard not available. Cluster is managed via kubectl."

health: ## Check cluster health (Talos API)
	@echo "$(GREEN)[INFO]$(NC) Checking Talos cluster health..."
	@talosctl --context talos-local health 2>/dev/null || echo "$(YELLOW)[WARN]$(NC) Talos API not accessible. Use 'kubectl get nodes' instead."

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

logs-talos: ## Show logs from all Talos nodes
	@echo "$(GREEN)[INFO]$(NC) Streaming logs from all nodes (Ctrl+C to stop)"
	@talosctl --context talos-local logs -f

containers: ## Show all Talos containers
	@docker ps --filter name=talos-local --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

nodes: ## List all Kubernetes nodes
	@kubectl get nodes -o wide

pods: ## List all pods in all namespaces
	@kubectl get pods -A -o wide

services: ## List all services in all namespaces
	@kubectl get svc -A

events: ## Show recent cluster events
	@kubectl get events -A --sort-by='.lastTimestamp' | tail -20

top-nodes: ## Show node resource usage
	@kubectl top nodes

top-pods: ## Show pod resource usage
	@kubectl top pods -A

restart: destroy-infra deploy-infra ## Destroy and recreate the cluster

clean: destroy-infra ## Alias for destroy-infra

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
	@echo "PersistentVolumeClaims:"
	@kubectl get pvc -n monitoring

##
## Traefik Ingress Targets
##

deploy-traefik: ## Deploy Traefik ingress controller and configure DNS
	@echo "$(GREEN)[INFO]$(NC) Deploying Traefik ingress controller..."
	@chmod +x scripts/deploy-traefik.sh
	@./scripts/deploy-traefik.sh

destroy-traefik: ## Remove Traefik ingress controller
	@chmod +x scripts/destroy-traefik.sh
	@./scripts/destroy-traefik.sh

destroy-traefik-full: ## Remove Traefik and clean DNS entries
	@chmod +x scripts/destroy-traefik.sh
	@./scripts/destroy-traefik.sh --clean-dns

setup-dns: ## Configure /etc/hosts for .local.dev domains
	@echo "$(GREEN)[INFO]$(NC) Setting up DNS entries..."
	@chmod +x infrastructure/traefik/setup-dns.sh
	@sudo infrastructure/traefik/setup-dns.sh

endpoints: ## Show all accessible endpoints
	@echo "$(GREEN)[INFO]$(NC) Available Endpoints"
	@echo ""
	@echo "Traefik Dashboard:"
	@echo "  http://traefik.local.dev/dashboard/"
	@echo ""
	@if kubectl get namespace monitoring >/dev/null 2>&1; then \
		if kubectl get svc -n monitoring grafana >/dev/null 2>&1; then \
			echo "Grafana:"; \
			echo "  http://grafana.local.dev"; \
			echo "  Credentials: admin / admin"; \
			echo ""; \
		fi; \
		if kubectl get svc -n monitoring prometheus >/dev/null 2>&1; then \
			echo "Prometheus:"; \
			echo "  http://prometheus.local.dev"; \
			echo ""; \
		fi; \
	fi
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		if kubectl get svc -n argocd argocd-server >/dev/null 2>&1; then \
			echo "ArgoCD:"; \
			echo "  http://argocd.local.dev"; \
			echo "  Username: admin"; \
			echo "  Password: Run 'make argocd-password'"; \
			echo ""; \
		fi; \
	fi
	@echo "Application Endpoints:"
	@kubectl get ingressroute -A -o custom-columns=HOST:.spec.routes[*].match 2>/dev/null | grep -vE "traefik|grafana|prometheus|argocd|HOST" | sed 's/.*Host(`//g' | sed 's/`).*//g' | sed 's/^/  http:\/\//g' || echo "  (No applications deployed yet)"
	@echo ""
	@echo "To test endpoints: make test-endpoints"

test-endpoints: ## Test endpoint accessibility
	@echo "$(GREEN)[INFO]$(NC) Testing endpoint accessibility..."
	@echo ""
	@echo -n "Traefik Dashboard: "
	@curl -s -o /dev/null -w "%%{http_code}" --max-time 5 http://traefik.local.dev/dashboard/ 2>/dev/null && echo " $(GREEN)✓ OK$(NC)" || echo " $(YELLOW)✗ Not responding$(NC)"
	@if kubectl get namespace monitoring >/dev/null 2>&1; then \
		if kubectl get svc -n monitoring grafana >/dev/null 2>&1; then \
			echo -n "Grafana:           "; \
			curl -s -o /dev/null -w "%%{http_code}" --max-time 5 http://grafana.local.dev 2>/dev/null && echo " $(GREEN)✓ OK$(NC)" || echo " $(YELLOW)✗ Not responding$(NC)"; \
		fi; \
		if kubectl get svc -n monitoring prometheus >/dev/null 2>&1; then \
			echo -n "Prometheus:        "; \
			curl -s -o /dev/null -w "%%{http_code}" --max-time 5 http://prometheus.local.dev 2>/dev/null && echo " $(GREEN)✓ OK$(NC)" || echo " $(YELLOW)✗ Not responding$(NC)"; \
		fi; \
	fi
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		if kubectl get svc -n argocd argocd-server >/dev/null 2>&1; then \
			echo -n "ArgoCD:            "; \
			curl -s -o /dev/null -w "%%{http_code}" --max-time 5 http://argocd.local.dev 2>/dev/null && echo " $(GREEN)✓ OK$(NC)" || echo " $(YELLOW)✗ Not responding$(NC)"; \
		fi; \
	fi
	@echo ""

logs-traefik: ## Show Traefik logs
	@kubectl logs -n traefik -l app.kubernetes.io/name=traefik -f

traefik-status: ## Show Traefik status and IngressRoutes
	@echo "$(GREEN)[INFO]$(NC) Traefik Status"
	@echo ""
	@echo "Pods:"
	@kubectl get pods -n traefik -o wide
	@echo ""
	@echo "IngressRoutes:"
	@kubectl get ingressroute -A
	@echo ""
	@echo "Services:"
	@kubectl get svc -n traefik

##
## ArgoCD Targets
##

argocd-password: ## Get ArgoCD admin password
	@echo "$(GREEN)[INFO]$(NC) ArgoCD Admin Credentials"
	@echo "  Username: admin"
	@echo -n "  Password: "
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "$(YELLOW)Not available yet$(NC)"
	@echo ""
	@echo ""
	@echo "Access ArgoCD at: https://argocd.local.dev/"

argocd-apps: ## List all ArgoCD applications
	@kubectl get applications -n argocd

argocd-status: ## Show ArgoCD status
	@echo "$(GREEN)[INFO]$(NC) ArgoCD Status"
	@echo ""
	@echo "Pods:"
	@kubectl get pods -n argocd
	@echo ""
	@echo "Applications:"
	@kubectl get applications -n argocd 2>/dev/null || echo "No applications deployed yet"

logs-argocd: ## Show ArgoCD server logs
	@kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f

logs-argocd-repo: ## Show ArgoCD repo-server logs
	@kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f

# Catch-all target for passing arguments to destroy-infra
%:
	@:
