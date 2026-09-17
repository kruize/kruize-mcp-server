# Kruize MCP Server — Deployment Guide

This guide covers every supported deployment scenario in detail:

1. [Prerequisites](#prerequisites)
2. [Step 0 — Deploy Kruize](#step-0--deploy-kruize)
3. [Option A — Local JAR](#option-a--local-jar)
4. [Option B — Minikube](#option-b--minikube)
5. [Option C — OpenShift](#option-c--openshift)
6. [Connect an AI Client](#connect-an-ai-client)
7. [Verify the Deployment](#verify-the-deployment)
8. [Configuration Reference](#configuration-reference)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Common Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Java | 21+ | Required to build and run the JAR |
| Maven (or `./mvnw`) | 3.9+ | Build tool (wrapper included) |
| Git | any | Clone the repository |

### Per-Environment Requirements

| Environment | Additional Requirements |
|-------------|------------------------|
| Local JAR | Kruize accessible on your network |
| Minikube | `minikube`, `kubectl`, Docker |
| OpenShift | `oc` CLI, Docker (or Podman), container registry access |

---

## Step 0 — Deploy Kruize

The Kruize MCP Server is a bridge to [Kruize](https://github.com/kruize/autotune) — it needs a running Kruize instance to work. If you already have one, skip to the deployment option you need.

### Deploy Kruize on Minikube

```bash
git clone https://github.com/kruize/kruize-demos.git
cd kruize-demos/monitoring/local_monitoring

# -f: fresh Minikube setup (also deploys Prometheus)
# -c minikube: target platform
# -e container: deployment mode
./local_monitoring_demo.sh -c minikube -f -e container
```

Verify Kruize is running:

```bash
kubectl get pods -n monitoring | grep kruize
# Expected: STATUS = Running
```

### Deploy Kruize on OpenShift

```bash
git clone https://github.com/kruize/kruize-demos.git
cd kruize-demos/monitoring/local_monitoring
./local_monitoring_demo.sh -c openshift -e container
```

Verify:

```bash
oc get pods -n openshift-tuning | grep kruize
```

---

## Option A — Local JAR

This is the fastest way to get started. The server runs as a regular Java process on your machine and connects to any Kruize instance you can reach.

### 1. Clone and Build

```bash
git clone https://github.com/kruize/kruize-mcp-server.git
cd kruize-mcp-server
./mvnw clean package -DskipTests
```

The build produces: `target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar`

### 2. Run

**Kruize on localhost (default):**

```bash
# Kruize defaults to port 8080, so run the MCP server on a different port to avoid conflicts
QUARKUS_HTTP_PORT=8082 java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar
```

**Kruize on Minikube:**

```bash
KRUIZE_URL="http://$(minikube ip):$(kubectl get svc kruize -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')"
KRUIZE_URL=$KRUIZE_URL java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar
```

**Kruize on OpenShift:**

```bash
KRUIZE_URL=$(oc get route kruize -n openshift-tuning --template='http://{{ .spec.host }}')
KRUIZE_URL=$KRUIZE_URL java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar
```

**Custom port (to avoid conflicts):**

```bash
QUARKUS_HTTP_PORT=8082 KRUIZE_URL=http://<host>:<port> \
  java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar
```

### 3. Confirm It Started

```bash
# Default port (8080):
curl http://localhost:8080/q/health/ready
# Custom port (for example, 8082):
curl http://localhost:8082/q/health/ready
# Expected: {"status":"UP",...}
```

MCP endpoint (default port): `http://localhost:8080/mcp`
MCP endpoint (custom port):  `http://localhost:8082/mcp`

### Development Mode (auto-reload)

```bash
./mvnw quarkus:dev
```

The server restarts automatically when source files change, making it ideal for tool development.

---

## Option B — Minikube

Deploys the MCP server as a Kubernetes `Deployment` inside Minikube, alongside Kruize. The manifest uses a pre-built image so no local build is needed.

### 1. Clone the repository

```bash
git clone https://github.com/kruize/kruize-mcp-server.git
cd kruize-mcp-server
```

### 2. Get the Kruize URL

```bash
KRUIZE_IP=$(minikube ip)
KRUIZE_PORT=$(kubectl get svc kruize -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')
echo "KRUIZE_URL=http://$KRUIZE_IP:$KRUIZE_PORT"
```

### 3. Update `KRUIZE_URL` in the manifest

The manifest has a placeholder that **must** be replaced with the actual Kruize URL before deploying:

```yaml
# manifests/kruize-mcp-server-minikube.yaml
env:
  - name: KRUIZE_URL
    value: "http://<minikube-ip>:<kruize-port>"   # ← replace with the URL from step 2
```

Update it in-place with `sed`:

```bash
KRUIZE_URL="http://$(minikube ip):$(kubectl get svc kruize -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')"
sed -i "s|http://<minikube-ip>:<kruize-port>|$KRUIZE_URL|g" manifests/kruize-mcp-server-minikube.yaml
```

### 4. Deploy

```bash
kubectl apply -f manifests/kruize-mcp-server-minikube.yaml

# Wait until the pod is ready
kubectl wait --for=condition=ready pod -l app=kruize-mcp-server \
  -n monitoring --timeout=120s
```

### 5. Verify the Deployment

```bash
kubectl get pods -n monitoring -l app=kruize-mcp-server
# Expected: STATUS = Running, READY = 1/1

kubectl get svc -n monitoring kruize-mcp-server-service
# Expected: NodePort service on port 8082
```

Check health:

```bash
# Port-forward first
kubectl port-forward -n monitoring svc/kruize-mcp-server-service 8082:8082

# In another terminal
curl http://localhost:8082/q/health/ready
```

### 6. Access the MCP Endpoint

Keep the port-forward running:

```bash
kubectl port-forward -n monitoring svc/kruize-mcp-server-service 8082:8082
```

MCP endpoint: `http://localhost:8082/mcp`

### Logs

```bash
kubectl logs -f deployment/kruize-mcp-server -n monitoring
```

---

## Option C — OpenShift

Deploys to OpenShift in the `openshift-tuning` namespace alongside Kruize. The OpenShift manifest includes a `Route` with SSE-compatible HAProxy timeout annotations and uses a pre-built image so no local build is needed.

### 1. Clone the repository

```bash
git clone https://github.com/kruize/kruize-mcp-server.git
cd kruize-mcp-server
```

### 2. Deploy

```bash
oc apply -f manifests/kruize-mcp-server-openshift.yaml -n openshift-tuning
```

Wait for the pod to become ready:

```bash
oc wait --for=condition=ready pod -l app=kruize-mcp-server \
  -n openshift-tuning --timeout=120s
```

### 3. Get the Route URL

The manifest creates a `Route` automatically. Retrieve the URL:

```bash
MCP_ROUTE=$(oc get route kruize-mcp-server-service -n openshift-tuning \
  --template='http://{{ .spec.host }}')
echo "MCP endpoint: $MCP_ROUTE/mcp"
```

MCP endpoint: `http://<route-host>/mcp`

### 4. Verify

```bash
# Check pod health
curl http://<route-host>/q/health/ready

# Check MCP endpoint is reachable (405 is expected for GET)
curl -v http://<route-host>/mcp
```

### Logs

```bash
oc logs -f deployment/kruize-mcp-server -n openshift-tuning
```

> **Want to use your own image?** See [Option A — Local JAR](#option-a--local-jar) to build the JAR, then build and push a container image. Update the `image:` field in `manifests/kruize-mcp-server-openshift.yaml` before running `oc apply`.

---

## Connect an AI Client

Replace `<mcp-endpoint>` with the URL from your deployment:

| Environment | MCP endpoint |
|-------------|-------------|
| Local JAR | `http://localhost:8080/mcp` |
| Minikube (port-forward) | `http://localhost:8082/mcp` |
| OpenShift | `http://<route-host>/mcp` |

### MCP Inspector

The easiest way to verify the server is working:

```bash
# Install once
npm install -g @modelcontextprotocol/inspector@0.11.0

# Launch
npx @modelcontextprotocol/inspector <mcp-endpoint>
```

In the browser UI:
1. Confirm the URL in the connection bar matches your endpoint
2. Click **Connect** — the status indicator should turn green
3. Click **List Tools** — you should see the five Kruize tools
4. Select a tool, click **Call Tool**, and review the results

### Claude Desktop

Config file locations:
- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`
- Linux: `~/.config/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "kruize": {
      "url": "http://localhost:8080/mcp",
      "type": "streamable-http",
      "timeout": 600
    }
  }
}
```

Restart Claude Desktop after saving.

### Bob

Add to your `~/.bob/settings/mcp.json` (or workspace `.bob/mcp.json`):

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

You can register multiple endpoints side-by-side (e.g., local and remote):

```json
{
  "mcpServers": {
    "kruize-local": {
      "url": "http://localhost:8080/mcp",
      "type": "streamable-http"
    },
    "kruize-openshift": {
      "url": "http://<route-host>/mcp",
      "type": "streamable-http"
    }
  }
}
```

---

## Verify the Deployment

### Health Checks

| Endpoint | Purpose | Expected result |
|----------|---------|-----------------|
| `GET /q/health` | Overall health | `{"status":"UP"}` |
| `GET /q/health/live` | Liveness (app running?) | `{"status":"UP"}` |
| `GET /q/health/ready` | Readiness (Kruize reachable?) | `{"status":"UP"}` |

```bash
curl http://<host>:<port>/q/health/ready
```

A `DOWN` readiness response means the server cannot reach Kruize — check the `KRUIZE_URL` value.

### MCP Endpoint Smoke Test

```bash
# GET returns 405 — this is correct, MCP uses POST
curl -v http://<host>:<port>/mcp
# Expected: HTTP/1.1 405 Method Not Allowed

# Full MCP handshake
curl -s -X POST http://<host>:<port>/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}},"id":1}'
```

---

## Configuration Reference

All settings live in [`src/main/resources/application.properties`](../src/main/resources/application.properties). They can be overridden with environment variables at runtime (Quarkus convention: replace `.` with `_` and uppercase).

### Key Settings

| Property | Default | Description |
|----------|---------|-------------|
| `KRUIZE_URL` | `http://localhost:8080` | Kruize backend URL |
| `quarkus.http.port` | `8080` | MCP server HTTP port |
| `quarkus.http.idle-timeout` | `30M` | SSE connection idle timeout |
| `quarkus.rest-client.*.connect-timeout` | `10000` ms | Kruize connection timeout |
| `quarkus.rest-client.*.read-timeout` | `120000` ms | Kruize response timeout |
| `quarkus.mcp.server.auto-ping-interval` | `15s` | SSE keepalive ping interval |

---

## Troubleshooting

### Server not starting

```bash
# Check if the port is already in use
lsof -i :8080          # macOS / Linux
netstat -ano | findstr :8080   # Windows

# Run on a different port
QUARKUS_HTTP_PORT=8090 java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar
```

### Readiness probe DOWN

The server cannot reach Kruize. Common causes:

| Symptom in `/q/health/ready` | Likely cause |
|-----------------------------|--------------|
| `"Connection refused"` | Wrong port or Kruize not running |
| `"Unknown host"` | Wrong hostname or DNS issue |
| `"Connection timeout"` | Network policy blocking traffic |
| `"statusCode": 503` | Kruize is running but unhealthy |

Fix: verify `KRUIZE_URL` is correct and reachable from the pod:

```bash
# From inside the pod
kubectl exec -it <pod-name> -n monitoring -- \
  curl http://<kruize-url>/health
```

### SSE stream disconnected

SSE connections are terminated by intermediate proxies with short timeouts (common on OpenShift).

**On OpenShift** — the manifests set a 5-minute HAProxy timeout, so SSE connections may still be terminated after five minutes:
```yaml
haproxy.router.openshift.io/timeout: 5m
haproxy.router.openshift.io/disable_cookies: "true"
```
To extend this, edit `manifests/kruize-mcp-server-openshift.yaml` and increase the annotation value (e.g. `30m`) before applying.

**On Minikube / local** — no fix needed; NodePort services connect directly to pods.

### No tools returned by MCP client

1. Confirm the server is reachable: `curl -v <mcp-endpoint>`
2. Confirm the readiness check passes: `curl <host>/q/health/ready`
3. Confirm the client URL has **no trailing slash**: use `/mcp` not `/mcp/`
4. Check server logs for errors:
   ```bash
   # Kubernetes
   kubectl logs -f deployment/kruize-mcp-server -n monitoring
   # Local
   # Inspect stdout where you ran the JAR
   ```

### Port conflicts on Minikube

Kruize uses ports 8080 and 8081. The MCP server defaults to 8080. When running both locally, override:

```bash
QUARKUS_HTTP_PORT=8082 KRUIZE_URL=http://... \
  java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar
```
