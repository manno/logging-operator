#!/usr/bin/env bash
set -euo pipefail

# Build with goreleaser for local development
# Requires: goreleaser (brew install goreleaser)

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-manno/logging-operator}"
VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "dev")

export GITHUB_REPOSITORY

echo "Building logging-operator:${VERSION} with goreleaser"

# Check if goreleaser is installed
if ! command -v goreleaser &> /dev/null; then
    echo "❌ goreleaser not found. Installing..."
    echo ""
    echo "Install with:"
    echo "  macOS: brew install goreleaser"
    echo "  Linux: https://goreleaser.com/install/"
    exit 1
fi

# Build binaries and images using goreleaser
# Use --snapshot for non-tag builds (dev builds)
if [[ "$VERSION" == *"dirty"* ]] || ! git describe --exact-match --tags HEAD &>/dev/null; then
    echo "📦 Building snapshot (dev build)..."
    goreleaser build --snapshot --clean --single-target

    # Build Docker image manually for local testing
    if [ -f "dist/logging-operator_linux_amd64_v1/logging-operator" ]; then
        cp dist/logging-operator_linux_amd64_v1/logging-operator ./
    elif [ -f "dist/logging-operator_linux_arm64/logging-operator" ]; then
        cp dist/logging-operator_linux_arm64/logging-operator ./
    fi

    docker build -f Dockerfile.suse -t "${GITHUB_REPOSITORY}:${VERSION}" -t "${GITHUB_REPOSITORY}:latest" .
    rm -f logging-operator
else
    echo "📦 Building release..."
    goreleaser release --clean
fi

echo "✅ Built: ${GITHUB_REPOSITORY}:${VERSION}"
echo ""
echo "Run with: docker run --rm ${GITHUB_REPOSITORY}:latest --help"
