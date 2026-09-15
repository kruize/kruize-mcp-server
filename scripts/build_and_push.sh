#!/bin/bash
set -euo pipefail

# Validate that a value matches an allowed pattern; exit on failure.
validate() {
    local name="$1" value="$2" pattern="$3"
    if [[ ! "${value}" =~ ^${pattern}$ ]]; then
        echo "Error: invalid value for ${name}: '${value}'" >&2
        exit 1
    fi
}

REGISTRY="${REGISTRY:-quay.io}"
REPO_NAME="${REPO_NAME:-kruize/kruize-mcp-server}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PUSH_IMAGE="${PUSH_IMAGE:-false}"

while getopts "r:n:t:l:p:h" opt; do
    case ${opt} in
        r ) REGISTRY="$OPTARG" ;;
        n ) REPO_NAME="$OPTARG" ;;
        t ) IMAGE_TAG="$OPTARG" ;;
        l ) PLATFORMS="$OPTARG" ;;
        p ) PUSH_IMAGE="$OPTARG" ;;
        h )
            echo "Usage: $0 [OPTIONS]"
            echo "  -r REGISTRY    Container registry (default: quay.io)"
            echo "  -n REPO_NAME   Repository name (default: kruize/kruize-mcp-server)"
            echo "  -t TAG         Image tag (default: latest)"
            echo "  -l PLATFORMS   Target platforms (default: linux/amd64,linux/arm64)"
            echo "  -p PUSH        Push image true/false (default: false)"
            echo ""
            echo "Examples:"
            echo "  $0 -t v1.0.0 -p true"
            echo "  $0 -t dev -l linux/amd64"
            echo "  $0 -r docker.io -n myorg/kruize-mcp-server -t latest -p true"
            exit 0
            ;;
        \? ) echo "Invalid option: -$OPTARG"; exit 1 ;;
    esac
done

# Validate all user-supplied inputs before use in shell commands
# Registry: hostname with optional port (e.g. quay.io, localhost:5000)
validate "REGISTRY"  "${REGISTRY}"  '[a-zA-Z0-9._:-]+'
# Repo name: one or two path segments of alphanumeric/hyphen/underscore/dot
validate "REPO_NAME" "${REPO_NAME}" '[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)?'
# Tag: alphanumeric, dots, hyphens, underscores — no slashes or shell metacharacters
validate "IMAGE_TAG" "${IMAGE_TAG}" '[a-zA-Z0-9._-]+'
# Platforms: comma-separated linux/arch pairs
validate "PLATFORMS" "${PLATFORMS}" 'linux/(amd64|arm64|arm\/v7|s390x|ppc64le)(,linux/(amd64|arm64|arm\/v7|s390x|ppc64le))*'
# Push flag
if [[ "${PUSH_IMAGE}" != "true" && "${PUSH_IMAGE}" != "false" ]]; then
    echo "Error: -p must be 'true' or 'false', got '${PUSH_IMAGE}'" >&2
    exit 1
fi

IMAGE_NAME="${REGISTRY}/${REPO_NAME}:${IMAGE_TAG}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Detect container runtime: prefer docker, fall back to podman
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    RUNTIME="docker"
elif command -v podman &>/dev/null; then
    RUNTIME="podman"
else
    echo "Error: neither docker nor podman is available." >&2
    exit 1
fi

echo "Using runtime: ${RUNTIME}"
echo "Building: ${IMAGE_NAME} for ${PLATFORMS}"

# Maven build
cd "${PROJECT_ROOT}"
mvn clean package -DskipTests

# Multi-arch build
if [ "${RUNTIME}" = "docker" ]; then
    BUILDER_NAME="kruize-mcp-builder"
    if ! docker buildx inspect "${BUILDER_NAME}" &>/dev/null; then
        docker buildx create --name "${BUILDER_NAME}" --use --bootstrap
    else
        docker buildx use "${BUILDER_NAME}"
    fi

    if [ "${PUSH_IMAGE}" = "true" ]; then
        docker buildx build --platform="${PLATFORMS}" --tag "${IMAGE_NAME}" --provenance=false --sbom=false --push .
    else
        docker buildx build --platform="${PLATFORMS}" --tag "${IMAGE_NAME}" --provenance=false --sbom=false .
        echo "Image built but not pushed. Use -p true to push."
    fi

else
    # Podman: build each platform and combine into a manifest list
    MANIFEST="${IMAGE_NAME}-manifest"
    podman manifest rm "${MANIFEST}" 2>/dev/null || true
    podman manifest create "${MANIFEST}"

    IFS=',' read -ra PLATFORM_LIST <<< "${PLATFORMS}"
    for platform in "${PLATFORM_LIST[@]}"; do
        podman build --platform "${platform}" --manifest "${MANIFEST}" .
    done

    if [ "${PUSH_IMAGE}" = "true" ]; then
        podman manifest push "${MANIFEST}" "${IMAGE_NAME}"
    else
        echo "Image built but not pushed. Use -p true to push."
    fi
fi

echo "Done: ${IMAGE_NAME}"
