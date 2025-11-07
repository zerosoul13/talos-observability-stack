#!/bin/bash

# Deploy script for sample-app
# Applies Kubernetes manifests and waits for pods to be ready

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-default}"
APP_NAME="sample-app"

echo "===================================="
echo "Deploying Sample App"
echo "===================================="
echo "Namespace: ${NAMESPACE}"
echo "App: ${APP_NAME}"
echo ""

# Apply Kubernetes manifests
echo "Applying Kubernetes manifests..."
kubectl apply -f "${SCRIPT_DIR}/deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/service.yaml"
kubectl apply -f "${SCRIPT_DIR}/ingressroute.yaml"

echo ""
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=120s

if [ $? -ne 0 ]; then
    echo "ERROR: Deployment rollout failed"
    echo ""
    echo "Pod status:"
    kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME}
    echo ""
    echo "Pod logs:"
    kubectl logs -n ${NAMESPACE} -l app=${APP_NAME} --tail=50
    exit 1
fi

echo ""
echo "===================================="
echo "Deployment Successful"
echo "===================================="
echo ""

# Show deployment status
echo "Pods:"
kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME}
echo ""

echo "Service:"
kubectl get svc -n ${NAMESPACE} ${APP_NAME}
echo ""

echo "IngressRoute:"
kubectl get ingressroute -n ${NAMESPACE} ${APP_NAME}
echo ""

# Get pod logs
echo "===================================="
echo "Recent Pod Logs"
echo "===================================="
kubectl logs -n ${NAMESPACE} -l app=${APP_NAME} --tail=20 --prefix=true
echo ""

# Test endpoint
echo "===================================="
echo "Testing Application Endpoint"
echo "===================================="
echo ""

# Wait a moment for service to be ready
sleep 2

# Get service cluster IP
SERVICE_IP=$(kubectl get svc ${APP_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')

if [ -n "${SERVICE_IP}" ]; then
    echo "Testing health endpoint (ClusterIP: ${SERVICE_IP}:8080)..."
    kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
        curl -s "http://${SERVICE_IP}:8080/" || true
    echo ""
    echo ""

    echo "Testing metrics endpoint..."
    kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
        curl -s "http://${SERVICE_IP}:8080/metrics" | head -20 || true
    echo ""
fi

echo ""
echo "===================================="
echo "Access Information"
echo "===================================="
echo "Internal URL: http://${SERVICE_IP}:8080"
echo "External URL: http://app.local.dev (requires /etc/hosts entry)"
echo ""
echo "Endpoints:"
echo "  Health:  GET  /"
echo "  Metrics: GET  /metrics"
echo "  Data:    GET  /api/data"
echo "  Logs:    POST /api/logs"
echo ""
echo "To access externally, add to /etc/hosts:"
echo "  <traefik-external-ip> app.local.dev"
echo ""
echo "To view logs:"
echo "  kubectl logs -f -l app=${APP_NAME} -n ${NAMESPACE}"
echo ""
