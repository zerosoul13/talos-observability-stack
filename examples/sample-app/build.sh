#!/bin/bash

# Build script for sample-app
# Builds Docker image and loads it into the cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="sample-app"
IMAGE_TAG="${VERSION:-latest}"
IMAGE_FULL="${IMAGE_NAME}:${IMAGE_TAG}"

echo "===================================="
echo "Building Sample App Docker Image"
echo "===================================="
echo "Image: ${IMAGE_FULL}"
echo "Context: ${SCRIPT_DIR}"
echo ""

# Build Docker image
echo "Building Docker image..."
docker build -t "${IMAGE_FULL}" "${SCRIPT_DIR}"

if [ $? -ne 0 ]; then
    echo "ERROR: Docker build failed"
    exit 1
fi

echo ""
echo "Docker image built successfully: ${IMAGE_FULL}"
echo ""

# Check if we're using kind or Talos
if command -v kind &> /dev/null; then
    CLUSTER_NAME="${KIND_CLUSTER_NAME:-talos-dev}"

    # Check if kind cluster exists
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo "Loading image into kind cluster: ${CLUSTER_NAME}"
        kind load docker-image "${IMAGE_FULL}" --name "${CLUSTER_NAME}"

        if [ $? -eq 0 ]; then
            echo "Image loaded into kind cluster successfully"
        else
            echo "WARNING: Failed to load image into kind cluster"
        fi
    else
        echo "WARNING: kind cluster '${CLUSTER_NAME}' not found"
        echo "Image built but not loaded into any cluster"
    fi
else
    echo "INFO: kind not found, skipping cluster image load"
    echo "For Talos clusters, ensure the image is pushed to a registry accessible by the cluster"
fi

echo ""
echo "===================================="
echo "Build Complete"
echo "===================================="
echo "Image: ${IMAGE_FULL}"
echo ""
echo "Next steps:"
echo "  1. Deploy the app: ./deploy.sh"
echo "  2. Or manually: kubectl apply -f deployment.yaml -f service.yaml -f ingressroute.yaml"
echo ""
