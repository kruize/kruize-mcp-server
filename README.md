# Kruize MCP Server

A cloud-native MCP server designed to act as a bridge between AI models/Agentic workflows and the Kruize recommendations engine. Kruize MCP server exposes Kubernetes resource recommendation data, including idle workload detection, as simple, actionable tools for AI models.

## Quick Start

Choose your platform:
- **[OpenShift](#openshift)** - Deploy on OpenShift clusters
- **[Minikube](#minikube)** - Deploy on Minikube for local development

---

## OpenShift

### Deploy

```bash
# 1. Clone and build
git clone https://github.com:kruize/kruize-mcp-server.git
cd kruize-mcp-server
./mvnw install

# 2. Deploy Kruize
./local_monitoring_demo.sh -c openshift -e container

# 3. Build and push image
docker build -t <registry>/<username>/kruize-mcp-server:<tag> .
docker push <registry>/<username>/kruize-mcp-server:<tag>

# 4. Deploy MCP server (in openshift-tuning namespace)
oc apply -f manifests/kruize-mcp-server-openshift.yaml -n openshift-tuning
oc expose service kruize-mcp-server-service -n openshift-tuning

# 5. Get URL and connect Inspector
oc get route kruize-mcp-server-service -n openshift-tuning --template='{{ .spec.host }}'
npx @modelcontextprotocol/inspector http://<route-url>/mcp/
```

**Deployment Location:** `openshift-tuning` namespace (same as Kruize)

---

## Minikube

### Deploy

```bash
# 1. Clone
git clone https://github.com:kruize/kruize-mcp-server.git
cd kruize-mcp-server

# 2. Deploy Kruize (sets up Minikube + Prometheus)
git clone https://github.com/kruize/kruize-demos.git
cd kruize-demos/monitoring/local_monitoring
./local_monitoring_demo.sh -c minikube -f -e container

# 3. Get Kruize connection details
# Get Kruize URL (Minikube IP + NodePort)
KRUIZE_URL=$(echo "http://$(minikube ip):$(kubectl get svc kruize -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')")
echo "Kruize URL: $KRUIZE_URL"

# 4. Deploy MCP server
cd kruize-mcp-server
# Update the KRUIZE_URL in the manifest file with the value from above
# Edit manifests/kruize-mcp-server-minikube.yaml and replace <minikube-ip>:<kruize-port> with the actual URL
kubectl apply -f manifests/kruize-mcp-server-minikube.yaml
kubectl wait --for=condition=ready pod -l app=kruize-mcp-server -n monitoring --timeout=120s

# 5. Port forward and connect Inspector
kubectl port-forward -n monitoring service/kruize-mcp-server-service 8082:8082
npx @modelcontextprotocol/inspector http://localhost:8082/mcp/
```

**Note:** Kruize MCP server uses port 8082 (Kruize uses 8080/8081)

---
**Important:** After connecting with Inspector tool, verify the URL matches your deployment in the Inspector tool UI:
- OpenShift: Use the MCP server route URL from `oc get route kruize-mcp-server-service -n openshift-tuning`
- Minikube: Use `http://localhost:8082/mcp/` (after port-forward)
- Local JAR: Use `http://localhost:8080/mcp/` or `http://localhost:8082/mcp/` depending on configuration

---

## MCP Tools

- `listAllExperiments` - List all experiments
- `listAllRecommendations` - List resource optimization CPU/memory recommendations for all the containers
- `getCostOptimizedRecommendations` - Get cost-optimized CPU/memory recommendations for a container. Optionally by namespace
- `getPerformanceRecommendations` - Get performance-optimized CPU/memory recommendations for a container. Optionally by namespace
- `getIdleWorkloads` - Get idle workloads (CPU usage < 1 millicore). Optionally with cost and performance recommendations

---

## Local Development

### Run from JAR - OpenShift Configuration

```bash
# 1. Build the project
./mvnw clean install

# 2. Get your Kruize route URL
KRUIZE_URL=$(oc get route kruize -n openshift-tuning --template='http://{{ .spec.host }}')
echo "Kruize URL: $KRUIZE_URL"

# 3. Run the JAR file with Kruize URL (port 8080)
KRUIZE_URL=$KRUIZE_URL java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar

# 4. Connect Inspector
npx @modelcontextprotocol/inspector http://localhost:8080/mcp/
```

**Custom Kruize URL (if needed):**
```bash
# Replace with your actual Kruize route URL
KRUIZE_URL=http://kruize-openshift-tuning.apps.your-cluster.com java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar
```

### Run from JAR - Minikube Configuration

```bash
# 1. Build the project
./mvnw clean install

# 2. Get Kruize URL (Minikube IP + NodePort)
KRUIZE_URL=$(echo "http://$(minikube ip):$(kubectl get svc kruize -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')")
echo "Kruize URL: $KRUIZE_URL"

# 3. Run the JAR file (port 8082 to avoid conflict with Kruize on 8080/8081)
QUARKUS_HTTP_PORT=8082 KRUIZE_URL=$KRUIZE_URL java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar

# 4. Connect Inspector
npx @modelcontextprotocol/inspector http://localhost:8082/mcp/
```

**Custom Kruize URL (if needed):**
```bash
# Replace with your actual Kruize URL
QUARKUS_HTTP_PORT=8082 KRUIZE_URL=http://192.168.49.2:30080 java -jar target/kruize-mcp-server-1.0-SNAPSHOT-runner.jar
```
---

## Health Check API

The server includes comprehensive health check endpoints for monitoring and Kubernetes integration:

### Quick Test

```bash
# Test health endpoints (default port)
curl http://localhost:8080/q/health        # Overall health
curl http://localhost:8080/q/health/live   # Liveness probe
curl http://localhost:8080/q/health/ready  # Readiness probe

# Test with custom URL
curl http://localhost:8082/q/health        # Custom port
curl https://kruize-mcp.example.com/q/health  # Remote server
```

### Health Endpoints

- **`/q/health`** - Overall health status (aggregates all checks)
- **`/q/health/live`** - Liveness probe (triggers pod restart on failure)
- **`/q/health/ready`** - Readiness probe (removes pod from service on failure)

### Kubernetes Integration

Health probes are automatically configured in the Kubernetes manifests:
- **Liveness Probe**: Checks every 30s, restarts pod on failure
- **Readiness Probe**: Checks every 10s, removes from service on failure

Both probes verify Kruize API connectivity to ensure the service is operational.

### Documentation

- **[Health Check API Guide](docs/HEALTH_CHECK_API.md)** - Complete API reference
