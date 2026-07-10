#!/usr/bin/env bash

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored message
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Get the image tag from argument
IMAGE_TAG="${1:-}"

if [ -z "$IMAGE_TAG" ]; then
    print_error "Missing image tag argument"
    echo ""
    echo "Usage: ./scripts/deploy.sh sha-<short-commit-hash>"
    echo ""
    echo "Examples:"
    echo "  ./scripts/deploy.sh sha-a1b2c3d"
    echo "  ./scripts/deploy.sh sha-12345ab"
    echo ""
    exit 1
fi

# Validate image tag format (must start with sha-)
if [[ ! "$IMAGE_TAG" =~ ^sha- ]]; then
    print_warn "Image tag should start with 'sha-' for commit-pinned deployments"
    print_warn "Example: sha-a1b2c3d"
fi

# Set APP_NAME from directory name or use provided value
export APP_NAME="${APP_NAME:-$(basename "$PWD")}"

# Validate required environment variables
if [ -z "${DOCKERHUB_USERNAME:-}" ]; then
    print_error "Missing DOCKERHUB_USERNAME environment variable"
    echo ""
    echo "Export it before running:"
    echo "  export DOCKERHUB_USERNAME=<your-dockerhub-username>"
    echo ""
    exit 1
fi

# Export IMAGE_TAG for docker compose
export IMAGE_TAG

print_info "=========================================="
print_info "Deploying ${APP_NAME}"
print_info "=========================================="
print_info "Docker Hub User: ${DOCKERHUB_USERNAME}"
print_info "Image Tag: ${IMAGE_TAG}"
print_info "App Name: ${APP_NAME}"
echo ""

# Pull the latest images from Docker Hub
print_info "Pulling images from Docker Hub..."
docker compose -f docker-compose.prod.yml pull || {
    print_error "Failed to pull images. Please check:"
    echo "  - Docker Hub credentials are correct"
    echo "  - Images exist: ${DOCKERHUB_USERNAME}/${APP_NAME}-service-*:${IMAGE_TAG}"
    echo "  - You have access to these images"
    exit 1
}

# Start the services and block until healthchecks pass (or time out)
print_info "Starting services..."
docker compose -f docker-compose.prod.yml up -d --remove-orphans --wait --wait-timeout 60 || {
    print_error "Failed to start services (or they did not become healthy in time)"
    docker compose -f docker-compose.prod.yml logs
    exit 1
}

echo ""
print_info "Services started successfully!"
echo ""

# Display running services
print_info "Running services:"
docker compose -f docker-compose.prod.yml ps

echo ""
print_info "=========================================="
print_info "Deployment complete!"
print_info "=========================================="
echo ""
echo "Next steps:"
echo "  - Check service health: curl http://localhost:8080/service-a/health"
echo "  - View logs: docker compose -f docker-compose.prod.yml logs -f"
echo "  - Stop services: docker compose -f docker-compose.prod.yml down"
echo ""
