#!/bin/bash

# =============================================================================
# AWX Image Update Script for JFrog Artifactory
# =============================================================================
# This script pulls the latest AWX-related images and pushes them to your
# JFrog Artifactory registry to avoid Docker Hub rate limiting.
#
# Usage: ./scripts/update-awx-images.sh [version]
# Example: ./scripts/update-awx-images.sh 23.5.1
#          ./scripts/update-awx-images.sh latest
# =============================================================================

set -eo pipefail

# Configuration
JFROG_REGISTRY="forgea37.jfrog.io"
JFROG_REPO="complex-demo-docker-local"
AWX_VERSION="${1:-latest}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

error() {
    echo -e "${RED}❌${NC} $1"
}

# Check if Docker is running
if ! docker info &> /dev/null; then
    error "Docker is not running. Please start Docker and try again."
    exit 1
fi

log "🚀 Starting AWX image update process..."
log "Target registry: ${JFROG_REGISTRY}/${JFROG_REPO}"
log "AWX Version: ${AWX_VERSION}"

# Images to update (name:source_image pairs)
IMAGES=(
    "memcached:memcached:1.6-alpine"
    "rabbitmq:rabbitmq:3.11-management-alpine"
    "awx:quay.io/ansible/awx:${AWX_VERSION}"
    "awx-ee:quay.io/ansible/awx-ee:${AWX_VERSION}"
)

# Function to pull, tag, and push an image
update_image() {
    local name=$1
    local source=$2
    local target="${JFROG_REGISTRY}/${JFROG_REPO}/${name}"
    
    log "📥 Pulling ${source}..."
    if docker pull "${source}"; then
        success "Pulled ${source}"
    else
        error "Failed to pull ${source}"
        return 1
    fi
    
    log "🏷️  Tagging as ${target}..."
    if docker tag "${source}" "${target}"; then
        success "Tagged ${target}"
    else
        error "Failed to tag ${target}"
        return 1
    fi
    
    log "📤 Pushing ${target}..."
    if docker push "${target}"; then
        success "Pushed ${target}"
    else
        error "Failed to push ${target}"
        return 1
    fi
    
    # Add version tag if not latest
    if [[ "${AWX_VERSION}" != "latest" && ("${name}" == "awx" || "${name}" == "awx-ee") ]]; then
        local versioned_target="${JFROG_REGISTRY}/${JFROG_REPO}/${name}:${AWX_VERSION}"
        log "🏷️  Creating version tag ${versioned_target}..."
        docker tag "${source}" "${versioned_target}"
        docker push "${versioned_target}"
        success "Pushed versioned tag ${versioned_target}"
    fi
}

# Update all images
log "🔄 Updating AWX images..."
for image_pair in "${IMAGES[@]}"; do
    name=$(echo "$image_pair" | cut -d: -f1)
    source=$(echo "$image_pair" | cut -d: -f2-)
    
    echo ""
    log "Processing ${name}..."
    if update_image "${name}" "${source}"; then
        success "Successfully updated ${name}"
    else
        error "Failed to update ${name}"
        exit 1
    fi
done

echo ""
success "🎉 All AWX images successfully updated in Artifactory!"

# Display summary
log "📋 Updated images:"
for image_pair in "${IMAGES[@]}"; do
    name=$(echo "$image_pair" | cut -d: -f1)
    echo "  • ${JFROG_REGISTRY}/${JFROG_REPO}/${name}:latest"
done

if [[ "${AWX_VERSION}" != "latest" ]]; then
    echo "  • ${JFROG_REGISTRY}/${JFROG_REPO}/awx:${AWX_VERSION}"
    echo "  • ${JFROG_REGISTRY}/${JFROG_REPO}/awx-ee:${AWX_VERSION}"
fi

echo ""
log "💡 Next steps:"
echo "  1. Update Terraform AWX module if needed"
echo "  2. Run: cd terraform && make apply ENV=dev REGION=us-east-2"
echo "  3. AWX will use images from your Artifactory registry"

# Cleanup local images (optional)
read -p "🗑️  Remove local copies of pulled images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "🧹 Cleaning up local images..."
    for image_pair in "${IMAGES[@]}"; do
        name=$(echo "$image_pair" | cut -d: -f1)
        source=$(echo "$image_pair" | cut -d: -f2-)
        docker rmi "${source}" "${JFROG_REGISTRY}/${JFROG_REPO}/${name}:latest" 2>/dev/null || true
    done
    success "Local images cleaned up"
fi

log "✨ AWX image update completed successfully!" 