# Kruize MCP Server - Quick Start Guide for Minikube

Get your Kruize MCP Server up and running on Minikube in minutes!

## Prerequisites

- Minikube running
- kubectl configured
- Node.js and npm installed
- Docker image available (local or registry)
- **Kruize deployed on Minikube** (see Step 0 below)

## Step 0: Deploy Kruize (If Not Already Running)

Before deploying the MCP server, ensure Kruize is running in your Minikube cluster.

### Using Kruize Demo Scripts:

```bash
# Clone kruize-demos repository
git clone https://github.com/kruize/kruize-demos.git
cd kruize-demos/monitoring/local_monitoring

# Deploy Kruize on Minikube with local monitoring demo
# The -f flag sets up both Minikube and Prometheus
./local_monitoring_demo.sh -c minikube -f -e container
```

**Note:** The `-f` flag automatically sets up Minikube and deploys Prometheus along with Kruize.

### Verify Kruize is Running:

```bash
# Check Kruize pods
kubectl get pods -n monitoring | grep kruize

# Should see kruize pod in Running status
```

**Note:** The MCP server needs to connect to Kruize, so ensure Kruize is deployed and running before proceeding.

---

## Quick Start

### Step 1: Deploy to Minikube (1 minute)

**Note:** Before deploying, update the manifest file with KRUIZE_URL to `http://<minikube-ip>:<kruize-port>`.

```bash
# Deploy using the provided manifest
kubectl apply -f manifests/kruize-mcp-server-minikube.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=kruize-mcp-server -n monitoring --timeout=120s
```

### Step 2: Verify Deployment (30 seconds)

```bash
# Check pod status
kubectl get pods -n monitoring -l app=kruize-mcp-server

# Should show: STATUS = Running, READY = 1/1
```

### Step 3: Access the Server (30 seconds)

**Terminal 1 - Start Port Forward:**
```bash
kubectl port-forward -n monitoring service/kruize-mcp-server-service 8082:8082
```

**Terminal 2 - Test Connection:**
```bash
curl -v http://localhost:8082/mcp/

# Expected: HTTP/1.1 405 Method Not Allowed (this is correct!)
```

### Step 4: Connect MCP Inspector (2 minutes)

**Install Inspector (one-time):**
```bash
npm install -g @modelcontextprotocol/inspector@0.11.0
```

**Launch Inspector:**
```bash
npx @modelcontextprotocol/inspector http://localhost:8082/mcp/
```

**In Browser (opens automatically):**

1. **Verify URL:**
   - Should show: `http://localhost:8082/mcp/`
   - If not, change it to this URL

2. **Connect:**
   - Click "Connect" button
   - Status should turn green

3. **Test Tools:**
   - Click "List Tools"
   - You should see 4 tools:
     - `listAllRecommendations`
     - `getCostOptimizedRecommendations`
     - `listAllExperiments`
     - `getIdleWorkloads`

4. **Call a Tool:**
   - Select `listAllExperiments`
   - Click "Call Tool"
   - View results

## You're Done! 🎉

Your Kruize MCP Server is now running and accessible via the Inspector tool.

---

## One-Command Deployment

For quick testing, use this single command:

```bash
kubectl run kruize-mcp-server --image=quay.io/kruize/kruize-mcp-server:0.0.1 \
  --port=8082 --env="KRUIZE_URL=http://<minikube-ip>:<kruize-port>" \
  --env="QUARKUS_HTTP_PORT=8082" -n monitoring && \
kubectl expose pod kruize-mcp-server --type=NodePort --port=8082 \
  --target-port=8082 --name=kruize-mcp-server-service -n monitoring && \
kubectl wait --for=condition=ready pod kruize-mcp-server -n monitoring --timeout=120s && \
echo "✅ MCP Server deployed! Run: kubectl port-forward -n monitoring service/kruize-mcp-server-service 8082:8082"
```

