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
IMAGE_NAME=""

while getopts "i:r:n:t:l:p:h" opt; do
    case ${opt} in
        i ) IMAGE_NAME="$OPTARG" ;;
        r ) REGISTRY="$OPTARG" ;;
        n ) REPO_NAME="$OPTARG" ;;
        t ) IMAGE_TAG="$OPTARG" ;;
        l ) PLATFORMS="$OPTARG" ;;
        p ) PUSH_IMAGE="$OPTARG" ;;
        h )
            echo "Usage: $0 [OPTIONS]"
            echo "  -i IMAGE       Full image reference, e.g. quay.io/user/kruize-mcp-server:v1.0.0"
            echo "                 (overrides -r, -n, -t when provided)"
            echo "  -r REGISTRY    Container registry (default: quay.io)"
            echo "  -n REPO_NAME   Repository name (default: kruize/kruize-mcp-server)"
            echo "  -t TAG         Image tag (default: latest)"
            echo "  -l PLATFORMS   Target platforms (default: linux/amd64,linux/arm64)"
            echo "  -p PUSH        Push image true/false (default: false)"
            echo ""
            echo "Examples:"
            echo "  $0 -i quay.io/user/kruize-mcp-server:v1.0.0 -p true"
            echo "  $0 -t v1.0.0 -p true"
            echo "  $0 -t dev -l linux/amd64"
            echo "  $0 -r docker.io -n myorg/kruize-mcp-server -t latest -p true"
            exit 0
            ;;
        \? ) echo "Invalid option: -$OPTARG"; exit 1 ;;
    esac
done

# If -i was given, parse registry/repo:tag from it; otherwise assemble from parts.
if [[ -n "${IMAGE_NAME}" ]]; then
    # Validate full image reference: registry/repo:tag (tag is optional, defaults to latest)
    validate "IMAGE" "${IMAGE_NAME}" '[a-zA-Z0-9._:-]+/[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)?(:[a-zA-Z0-9._-]+)?'
    # Split off tag (everything after the last colon, if any)
    if [[ "${IMAGE_NAME}" == *:* ]]; then
        IMAGE_TAG="${IMAGE_NAME##*:}"
        IMAGE_NAME="${IMAGE_NAME%:*}"
    fi
    # Split off registry (everything before the first slash)
    REGISTRY="${IMAGE_NAME%%/*}"
    REPO_NAME="${IMAGE_NAME#*/}"
    IMAGE_NAME="${REGISTRY}/${REPO_NAME}:${IMAGE_TAG}"
else
    # Validate all user-supplied inputs before use in shell commands
    # Registry: hostname with optional port (e.g. quay.io, localhost:5000)
    validate "REGISTRY"  "${REGISTRY}"  '[a-zA-Z0-9._:-]+'
    # Repo name: one or two path segments of alphanumeric/hyphen/underscore/dot
    validate "REPO_NAME" "${REPO_NAME}" '[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)?'
    # Tag: alphanumeric, dots, hyphens, underscores — no slashes or shell metacharacters
    validate "IMAGE_TAG" "${IMAGE_TAG}" '[a-zA-Z0-9._-]+'
    IMAGE_NAME="${REGISTRY}/${REPO_NAME}:${IMAGE_TAG}"
fi
# Platforms: comma-separated linux/arch pairs
validate "PLATFORMS" "${PLATFORMS}" 'linux/(amd64|arm64|arm\/v7|s390x|ppc64le)(,linux/(amd64|arm64|arm\/v7|s390x|ppc64le))*'
# Push flag
if [[ "${PUSH_IMAGE}" != "true" && "${PUSH_IMAGE}" != "false" ]]; then
    echo "Error: -p must be 'true' or 'false', got '${PUSH_IMAGE}'" >&2
    exit 1
fi
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

# Multi-platform builds can only be exported via a registry push.
# For local-only builds, fall back to the native platform so the image
# is immediately usable (docker --load / podman --tag).
NATIVE_PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
IS_MULTI_PLATFORM=false
if [[ "${PLATFORMS}" == *","* ]]; then
    IS_MULTI_PLATFORM=true
fi

if [ "${PUSH_IMAGE}" = "false" ] && [ "${IS_MULTI_PLATFORM}" = "true" ]; then
    echo "Warning: multi-platform builds require a registry push (--push)." >&2
    echo "  Falling back to native platform (${NATIVE_PLATFORM}) for local build." >&2
    PLATFORMS="${NATIVE_PLATFORM}"
fi

# Build
if [ "${RUNTIME}" = "docker" ]; then
    BUILDER_NAME="kruize-mcp-builder"
    if ! docker buildx inspect "${BUILDER_NAME}" &>/dev/null; then
        docker buildx create --name "${BUILDER_NAME}" --use --bootstrap
    else
        docker buildx use "${BUILDER_NAME}"
    fi

    if [ "${PUSH_IMAGE}" = "true" ]; then
        docker buildx build --platform="${PLATFORMS}" --tag "${IMAGE_NAME}" --provenance=false --sbom=false --push "${PROJECT_ROOT}"
    else
        # --load imports the single-platform image into the local Docker daemon
        docker buildx build --platform="${PLATFORMS}" --tag "${IMAGE_NAME}" --provenance=false --sbom=false --load "${PROJECT_ROOT}"
        echo "Image built and loaded locally as ${IMAGE_NAME}. Use -p true to push."
    fi

else
    # Podman: build each platform and combine into a manifest list
    MANIFEST="${IMAGE_NAME}-manifest"
    podman manifest rm "${MANIFEST}" 2>/dev/null || true
    podman manifest create "${MANIFEST}"

    IFS=',' read -ra PLATFORM_LIST <<< "${PLATFORMS}"
    for platform in "${PLATFORM_LIST[@]}"; do
        podman build --platform "${platform}" --manifest "${MANIFEST}" "${PROJECT_ROOT}"
    done

    if [ "${PUSH_IMAGE}" = "true" ]; then
        podman manifest push "${MANIFEST}" "${IMAGE_NAME}"
    else
        # Tag the manifest under the requested image name so it is locally usable
        podman tag "${MANIFEST}" "${IMAGE_NAME}"
        echo "Image built and tagged locally as ${IMAGE_NAME}. Use -p true to push."
    fi
fi

echo "Done: ${IMAGE_NAME}"
