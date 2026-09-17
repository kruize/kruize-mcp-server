# Kruize MCP Server

A cloud-native [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) server that bridges AI assistants and the [Kruize](https://github.com/kruize/autotune) resource optimization engine. It exposes Kubernetes workload recommendations — CPU, memory, and idle workload detection — as structured tools that any MCP-compatible AI client can invoke.

```
AI Client (Claude, Bob, etc.)
        │  MCP over HTTP/SSE
        ▼
Kruize MCP Server  ←→  Kruize API  ←→  Kubernetes cluster
```

## Prerequisites

| Tool | Purpose |
|------|---------|
| Java 21+ | Build and run the server (Local JAR only) |
| `kubectl` or `oc` | Deploy to Kubernetes / OpenShift |
| Kruize running | The backend recommendations engine |

> Need Kruize? → `git clone https://github.com/kruize/kruize-demos.git` and run `local_monitoring_demo.sh`. See the [Deployment Guide](docs/DEPLOYMENT_GUIDE.md#step-0--deploy-kruize) for details.

---

## Quick Start

### Local JAR (fastest)

```bash
git clone https://github.com/kruize/kruize-mcp-server.git
cd kruize-mcp-server
./mvnw clean package -DskipTests
KRUIZE_URL=http://<kruize-host>:<port> java -jar target/kruize-mcp-server-0.0.1-runner.jar
```

MCP endpoint: `http://localhost:8080/mcp`

### Minikube

```bash
# 1. Get Kruize URL
KRUIZE_URL="http://$(minikube ip):$(kubectl get svc kruize -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')"

# 2. Patch the manifest, then deploy
sed -i.bak "s|http://<minikube-ip>:<kruize-port>|$KRUIZE_URL|g" manifests/kruize-mcp-server-minikube.yaml
kubectl apply -f manifests/kruize-mcp-server-minikube.yaml
kubectl wait --for=condition=ready pod -l app=kruize-mcp-server -n monitoring --timeout=120s

# 3. Port-forward
kubectl port-forward -n monitoring svc/kruize-mcp-server-service 8082:8082
```

MCP endpoint: `http://localhost:8082/mcp`

### OpenShift

```bash
git clone https://github.com/kruize/kruize-mcp-server.git
cd kruize-mcp-server
oc apply -f manifests/kruize-mcp-server-openshift.yaml -n openshift-tuning

# Get the route URL
MCP_ROUTE=$(oc get route kruize-mcp-server-service -n openshift-tuning --template='http://{{ .spec.host }}')
echo "MCP endpoint: $MCP_ROUTE/mcp"
```

MCP endpoint: `http://<route-host>/mcp`

> For full step-by-step instructions and troubleshooting see the **[Deployment Guide](docs/DEPLOYMENT_GUIDE.md)**.

---

## Connect an AI Client

Once the server is running, connect your AI client to the MCP endpoint.

### MCP Inspector (browser-based testing)

```bash
npx @modelcontextprotocol/inspector <mcp-endpoint>
```

### Claude Desktop

Edit your Claude Desktop config file (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "kruize": {
      "url": "http://localhost:8080/mcp",
      "type": "streamable-http"
    }
  }
}
```

### Claude Code

```bash
claude mcp add --transport streamable-http kruize http://localhost:8080/mcp
```

### Bob

Add to your `~/.bob/settings/mcp.json`:

```json
{
  "mcpServers": {
    "kruize": {
      "url": "http://localhost:8080/mcp",
      "type": "streamable-http"
    }
  }
}
```

> Replace `http://localhost:8080/mcp` with your actual MCP endpoint (e.g. the OpenShift route URL or `http://localhost:8082/mcp` for Minikube). See the [Deployment Guide](docs/DEPLOYMENT_GUIDE.md#connect-an-ai-client) for all client options and multi-endpoint setup.

---

## Available Tools

| Tool | Description |
|------|-------------|
| `listAllExperiments` | List all Kruize experiments |
| `listAllRecommendations` | CPU/memory recommendations for all containers |
| `getCostOptimizedRecommendations` | Cost-optimized sizing, optionally filtered by namespace |
| `getPerformanceOptimizedRecommendations` | Performance-optimized sizing, optionally filtered by namespace |
| `getIdleWorkloads` | Workloads with near-zero CPU usage; optionally include recommendations |

Example prompts:
- _"Which workloads in the production namespace are over-provisioned for CPU?"_
- _"Show me idle workloads with cost-saving recommendations."_
- _"What are the performance recommendations for the auth service?"_

---

## Building and Pushing the Container Image

The [`scripts/build_and_push.sh`](scripts/build_and_push.sh) script handles multi-arch image builds and pushes using either Docker (buildx) or Podman. The Dockerfile uses a multi-stage build — compilation happens inside the container, so no local JDK or Maven installation is required.

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `-i IMAGE` | — | Full image reference (e.g. `quay.io/user/kruize-mcp-server:0.0.1`); overrides `-r`, `-n`, `-t` |
| `-r REGISTRY` | `quay.io` | Container registry hostname |
| `-n REPO_NAME` | `kruize/kruize-mcp-server` | Repository name |
| `-t TAG` | `latest` | Image tag |
| `-l PLATFORMS` | `linux/amd64,linux/arm64` | Comma-separated target platforms |
| `-p PUSH` | `false` | Push image after build (`true`/`false`) |

All options can also be set via environment variables (`REGISTRY`, `REPO_NAME`, `IMAGE_TAG`, `PLATFORMS`, `PUSH_IMAGE`).

### Examples

```bash
# Build and push using a full image reference (simplest form)
./scripts/build_and_push.sh -i quay.io/user/kruize-mcp-server:0.0.1 -p true

# Build only (no push)
./scripts/build_and_push.sh -i quay.io/user/kruize-mcp-server:0.0.1

# Build for a single platform
./scripts/build_and_push.sh -i quay.io/user/kruize-mcp-server:dev -l linux/amd64

# Build and push using individual flags
./scripts/build_and_push.sh -r docker.io -n myorg/kruize-mcp-server -t latest -p true
```

---

## Documentation

| Doc | Description |
|-----|-------------|
| [Deployment Guide](docs/DEPLOYMENT_GUIDE.md) | Full setup, client config, and troubleshooting for all environments |
| [MCP Tools Reference](docs/MCP_TOOLS_REFERENCE.md) | Tool parameters, example prompts, and sample output |
| [Health Check API](docs/HEALTH_CHECK_API.md) | Health endpoint reference |

---

## License

[Apache 2.0](LICENSE)
