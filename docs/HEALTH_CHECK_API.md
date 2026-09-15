# Health Check API for Kruize MCP Server

## Overview

The Kruize MCP Server now includes comprehensive health check capabilities for monitoring service health and Kubernetes integration. This implementation follows the MicroProfile Health specification using Quarkus SmallRye Health.

## Health Check Endpoints

### 1. Overall Health Status
**Endpoint:** `GET /q/health`

Returns the aggregated health status of all health checks (liveness + readiness).

**Response (Healthy):**
```json
{
  "status": "UP",
  "checks": [
    {
      "name": "Kruize API",
      "status": "UP",
      "data": {
        "responseTimeMs": 145
      }
    }
  ]
}
```

**Response (Unhealthy - HTTP 503):**
```json
{
  "status": "DOWN",
  "checks": [
    {
      "name": "Kruize API",
      "status": "DOWN",
      "data": {
        "error": "HTTP error",
        "statusCode": 503,
        "statusMessage": "Service Unavailable"
      }
    }
  ]
}
```

**Response (Unhealthy - HTTP 404):**
```json
{
  "status": "DOWN",
  "checks": [
    {
      "name": "Kruize API",
      "status": "DOWN",
      "data": {
        "error": "HTTP error",
        "statusCode": 404,
        "statusMessage": "Not Found"
      }
    }
  ]
}
```

**Response (Unhealthy - Connection Refused):**
```json
{
  "status": "DOWN",
  "checks": [
    {
      "name": "Kruize API",
      "status": "DOWN",
      "data": {
        "error": "Connection refused",
        "details": "io.netty.channel.AbstractChannel$AnnotatedConnectException: Connection refused: localhost/127.0.0.1:9999"
      }
    }
  ]
}
```

**Response (Unhealthy - Connection Timeout):**
```json
{
  "status": "DOWN",
  "checks": [
    {
      "name": "Kruize API",
      "status": "DOWN",
      "data": {
        "error": "Connection timeout",
        "details": "io.netty.channel.ConnectTimeoutException: connection timed out after 10000 ms: /3.135.106.210:9999"
      }
    }
  ]
}
```

### 2. Liveness Probe
**Endpoint:** `GET /q/health/live`

Checks if the application is running. Used by Kubernetes to determine if the pod should be restarted.

**Behavior:**
- Returns `UP` if the application is running
- Returns `DOWN` if the application has crashed or is unresponsive
- **Action on failure:** Kubernetes restarts the pod

**Response:**
```json
{
  "status": "UP",
  "checks": []
}
```

### 3. Readiness Probe
**Endpoint:** `GET /q/health/ready`

Checks if the application is ready to serve traffic by verifying Kruize API connectivity using the `/health` endpoint.

**Behavior:**
- Returns `UP` if Kruize API `/health` endpoint is accessible
- Returns `DOWN` if `/health` endpoint is unreachable
- **Action on failure:** Kubernetes removes pod from service endpoints (no traffic routed)
- **Note:** Pod is NOT restarted on readiness failure

**Response (Ready):**
```json
{
  "status": "UP",
  "checks": [
    {
      "name": "Kruize API",
      "status": "UP",
      "data": {
        "responseTimeMs": 45
      }
    }
  ]
}
```

**Response (Not Ready - HTTP 503):**
```json
{
  "status": "DOWN",
  "checks": [
    {
      "name": "Kruize API",
      "status": "DOWN",
      "data": {
        "error": "HTTP error",
        "statusCode": 503,
        "statusMessage": "Service Unavailable"
      }
    }
  ]
}
```

**Response (Not Ready - HTTP 404):**
```json
{
  "status": "DOWN",
  "checks": [
    {
      "name": "Kruize API",
      "status": "DOWN",
      "data": {
        "error": "HTTP error",
        "statusCode": 404,
        "statusMessage": "Not Found"
      }
    }
  ]
}
```

**Response (Not Ready - Connection Refused):**
```json
{
  "status": "DOWN",
  "checks": [
    {
      "name": "Kruize API",
      "status": "DOWN",
      "data": {
        "error": "Connection refused",
        "details": "io.netty.channel.AbstractChannel$AnnotatedConnectException: Connection refused: localhost/127.0.0.1:9999"
      }
    }
  ]
}
```

**Response (Not Ready - Connection Timeout):**
```json
{
  "status": "DOWN",
  "checks": [
    {
      "name": "Kruize API",
      "status": "DOWN",
      "data": {
        "error": "Connection timeout",
        "details": "io.netty.channel.ConnectTimeoutException: connection timed out after 10000 ms: /3.135.106.210:9999"
      }
    }
  ]
}
```

**Note:** The `/q/health` endpoint aggregates all health checks (liveness + readiness). Since only the readiness check (Kruize API) is implemented, both `/q/health` and `/q/health/ready` return the same response. The `/q/health/live` endpoint has no custom checks and always returns UP when the application is running.

## Kubernetes Integration

### Health Probe Configuration

Both Minikube and OpenShift manifests include health probes:

```yaml
livenessProbe:
  httpGet:
    path: /q/health/live
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 30
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /q/health/ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

### Probe Behavior

#### Liveness Probe
- **Initial Delay:** 30 seconds (allows application startup)
- **Check Interval:** Every 30 seconds
- **Timeout:** 5 seconds per check
- **Failure Threshold:** 3 consecutive failures trigger pod restart
- **Purpose:** Detect and recover from application crashes

#### Readiness Probe
- **Initial Delay:** 10 seconds (faster than liveness)
- **Check Interval:** Every 10 seconds
- **Timeout:** 5 seconds per check
- **Failure Threshold:** 3 consecutive failures remove pod from service
- **Purpose:** Ensure pod only receives traffic when backend is available

## Testing Health Checks

### 1. Test Locally

Start the application:
```bash
./mvnw quarkus:dev
```

Test health endpoints with curl:
```bash
# Default (localhost:8080)
curl http://localhost:8080/q/health
curl http://localhost:8080/q/health/live
curl http://localhost:8080/q/health/ready

# Custom port
curl http://localhost:8082/q/health

# Remote server
curl https://kruize-mcp.example.com/q/health
```

### 2. Test in Kubernetes

Deploy the application:
```bash
kubectl apply -f manifests/kruize-mcp-server-minikube.yaml
```

Check pod health:
```bash
# View pod status
kubectl get pods -n monitoring

# View pod events (shows probe failures)
kubectl describe pod <pod-name> -n monitoring

# View pod logs
kubectl logs <pod-name> -n monitoring
```

Test health endpoints:
```bash
# Port forward to access health endpoints
kubectl port-forward -n monitoring svc/kruize-mcp-server-service 8082:8082

# Test with curl
curl http://localhost:8082/q/health
curl http://localhost:8082/q/health/live
curl http://localhost:8082/q/health/ready
```

## Health Check Scenarios

### Scenario 1: Healthy System
- **Liveness:** UP
- **Readiness:** UP
- **Behavior:** Pod receives traffic normally

### Scenario 2: Kruize API Unavailable
- **Liveness:** UP (application still running)
- **Readiness:** DOWN (backend unavailable)
- **Behavior:** Pod removed from service, no traffic routed, pod NOT restarted

### Scenario 3: Application Crash
- **Liveness:** DOWN (application unresponsive)
- **Readiness:** DOWN (cannot check backend)
- **Behavior:** Kubernetes restarts the pod

### Scenario 4: Temporary Network Issue
- **Liveness:** UP
- **Readiness:** DOWN temporarily, then UP when network recovers
- **Behavior:** Pod removed from service during issue, automatically added back when recovered


## Benefits

1. **High Availability:** Automatic pod restart on application failure
2. **Zero Downtime:** Graceful handling of backend unavailability
3. **Service Mesh Ready:** Standard Kubernetes health probe support
4. **Operational Visibility:** Clear health status for monitoring
5. **Dependency Tracking:** Monitors Kruize API connectivity
6. **Kubernetes Native:** Follows Kubernetes best practices

## Monitoring and Alerting

### Recommended Metrics to Monitor

1. **Health Check Success Rate**
   - Track percentage of successful health checks
   - Alert on sustained failures

2. **Response Time**
   - Monitor health check response times
   - Alert on degraded performance

3. **Pod Restart Count**
   - Track liveness probe failures
   - Alert on frequent restarts

4. **Service Availability**
   - Monitor readiness probe status
   - Alert when pods are not ready

## Troubleshooting

### Pod Not Ready

**Symptoms:**
- Pod shows `0/1` ready in `kubectl get pods`
- No traffic routed to pod

**Diagnosis:**
```bash
# Check readiness probe status
kubectl describe pod <pod-name> -n monitoring

# Check logs for connection errors
kubectl logs <pod-name> -n monitoring

# Test Kruize API connectivity manually
kubectl exec -it <pod-name> -n monitoring -- curl http://kruize-url:8080/health
```

**Common Causes:**
1. **Incorrect KRUIZE_URL** - Health check will fail with connection errors
   - Example errors:
     - `"error": "Connection refused"` - Service not running or wrong port
     - `"error": "Unknown host"` - Invalid hostname/DNS issue
     - `"error": "Connection timeout"` - Network connectivity issue
   - Verify the `KRUIZE_URL` environment variable is set correctly
   - Check if the URL is reachable from the pod's network
2. **Kruize API returning errors** - Health check will report HTTP status
   - Example: `"statusCode": 503, "statusMessage": "Service Unavailable"`
   - Check Kruize API logs for the root cause
3. Network policy blocking traffic
4. Kruize service not running or unhealthy


## References

- [MicroProfile Health Specification](https://github.com/eclipse/microprofile-health)
- [Quarkus SmallRye Health Guide](https://quarkus.io/guides/smallrye-health)
- [Kubernetes Liveness and Readiness Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)