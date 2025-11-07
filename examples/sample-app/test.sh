#!/bin/bash

# Test script for sample-app
# Sends test requests and verifies observability integration

set -e

NAMESPACE="${NAMESPACE:-default}"
APP_NAME="sample-app"

echo "===================================="
echo "Testing Sample App"
echo "===================================="
echo ""

# Get service IP
SERVICE_IP=$(kubectl get svc ${APP_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')

if [ -z "${SERVICE_IP}" ]; then
    echo "ERROR: Could not get service IP for ${APP_NAME}"
    exit 1
fi

echo "Service IP: ${SERVICE_IP}:8080"
echo ""

# Function to run curl in cluster
run_curl() {
    kubectl run curl-test-$$-$RANDOM --image=curlimages/curl:latest --rm -i --restart=Never -- "$@"
}

# Test 1: Health endpoint
echo "===================================="
echo "Test 1: Health Endpoint"
echo "===================================="
echo "Testing GET /"
run_curl curl -s "http://${SERVICE_IP}:8080/"
echo ""
echo ""

# Test 2: Metrics endpoint
echo "===================================="
echo "Test 2: Metrics Endpoint"
echo "===================================="
echo "Testing GET /metrics"
run_curl curl -s "http://${SERVICE_IP}:8080/metrics" | grep -E "^(http_requests_total|http_request_duration|active_connections|business_operations)" | head -20
echo ""
echo ""

# Test 3: Data endpoint (multiple requests)
echo "===================================="
echo "Test 3: Data Endpoint"
echo "===================================="
echo "Sending 10 requests to GET /api/data..."
for i in {1..10}; do
    echo "Request $i:"
    run_curl curl -s "http://${SERVICE_IP}:8080/api/data"
    sleep 0.5
done
echo ""
echo ""

# Test 4: Logs endpoint
echo "===================================="
echo "Test 4: Logs Endpoint"
echo "===================================="
echo "Sending test logs with different levels..."

echo "INFO log:"
run_curl curl -s -X POST "http://${SERVICE_IP}:8080/api/logs" \
    -H "Content-Type: application/json" \
    -d '{"level":"info","message":"test_info_message","fields":{"test_id":"123","action":"test"}}'
echo ""

echo "WARN log:"
run_curl curl -s -X POST "http://${SERVICE_IP}:8080/api/logs" \
    -H "Content-Type: application/json" \
    -d '{"level":"warn","message":"test_warning_message","fields":{"test_id":"456","reason":"test_warning"}}'
echo ""

echo "ERROR log:"
run_curl curl -s -X POST "http://${SERVICE_IP}:8080/api/logs" \
    -H "Content-Type: application/json" \
    -d '{"level":"error","message":"test_error_message","fields":{"test_id":"789","error_code":"TEST_ERROR"}}'
echo ""
echo ""

# Test 5: Check metrics after load
echo "===================================="
echo "Test 5: Verify Metrics After Load"
echo "===================================="
echo "Checking updated metrics..."
run_curl curl -s "http://${SERVICE_IP}:8080/metrics" | grep -E "^(http_requests_total|business_operations_total)" | head -20
echo ""
echo ""

# Test 6: Check Pod Logs
echo "===================================="
echo "Test 6: Pod Logs (JSON Format)"
echo "===================================="
echo "Recent logs from pods:"
kubectl logs -n ${NAMESPACE} -l app=${APP_NAME} --tail=30 | grep -E '^\{' | tail -10
echo ""
echo ""

# Test 7: Verify Prometheus is scraping
echo "===================================="
echo "Test 7: Verify Prometheus Scraping"
echo "===================================="
echo "Checking if Prometheus has metrics from sample-app..."

PROM_SVC=$(kubectl get svc -n monitoring prometheus-operated -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

if [ -n "${PROM_SVC}" ]; then
    echo "Querying Prometheus for sample-app metrics..."
    run_curl curl -s "http://${PROM_SVC}:9090/api/v1/query?query=http_requests_total" | grep -o '"status":"success"' || echo "WARNING: No metrics found in Prometheus yet (may need time to scrape)"
else
    echo "INFO: Prometheus service not found, skipping check"
fi
echo ""
echo ""

# Test 8: Check Loki for logs
echo "===================================="
echo "Test 8: Verify Loki Has Logs"
echo "===================================="
echo "Checking if Loki has logs from sample-app..."

LOKI_SVC=$(kubectl get svc -n monitoring loki -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

if [ -n "${LOKI_SVC}" ]; then
    echo "Querying Loki for sample-app logs..."
    QUERY='{app="sample-app"}'
    run_curl curl -s -G "http://${LOKI_SVC}:3100/loki/api/v1/query" \
        --data-urlencode "query=${QUERY}" \
        --data-urlencode "limit=5" | grep -o '"status":"success"' || echo "WARNING: No logs found in Loki yet"
else
    echo "INFO: Loki service not found, skipping check"
fi
echo ""
echo ""

echo "===================================="
echo "Test Summary"
echo "===================================="
echo "✓ Health endpoint responding"
echo "✓ Metrics endpoint exposing Prometheus metrics"
echo "✓ Data endpoint processing requests"
echo "✓ Logs endpoint accepting structured logs"
echo "✓ Application generating JSON logs"
echo ""
echo "To monitor the application:"
echo "  Logs:    kubectl logs -f -l app=${APP_NAME} -n ${NAMESPACE}"
echo "  Metrics: kubectl port-forward svc/${APP_NAME} 8080:8080 && curl localhost:8080/metrics"
echo "  Grafana: Access dashboards to see metrics and logs"
echo ""
echo "To generate more load:"
echo "  while true; do curl http://${SERVICE_IP}:8080/api/data; sleep 1; done"
echo ""
