# Kruize MCP Tools Reference

This document describes each tool exposed by the Kruize MCP Server, including its parameters, example AI prompts, and a sample response.

## Table of Contents

1. [listAllExperiments](#listallexperiments)
2. [listAllRecommendations](#listallrecommendations)
3. [getCostOptimizedRecommendations](#getcostoptimizedrecommendations)
4. [getPerformanceOptimizedRecommendations](#getperformanceoptimizedrecommendations)
5. [getIdleWorkloads](#getidleworkloads)
6. [Notification Codes Reference](#notification-codes-reference)

---

## listAllExperiments

Returns the list of all Kruize experiments. An experiment is a monitoring configuration that tracks a specific workload.

### Parameters

None.

### Example Prompts

```
List all Kruize experiments.
What workloads is Kruize currently monitoring?
Show me all experiments.
```

### Sample Response

```json
[
  {
    "experiment_name": "my-app-experiment",
    "experiment_type": "container",
    "cluster_name": "default",
    "namespace": "production",
    "mode": "monitor",
    "status": "IN_PROGRESS"
  }
]
```

### Notes

- Returns `[]` when no experiments exist.
- `experiment_type` is typically `container` for standard Kubernetes workload monitoring.
- `mode` is `monitor` when Kruize is observing but not applying changes automatically.

---

## listAllRecommendations

Returns raw recommendation data for every container in every experiment. This is the full, unfiltered dataset — useful when you want to inspect the complete output or hand it off to an AI for analysis.

### Parameters

None.

### Example Prompts

```
Show me all recommendations.
What optimization opportunities does Kruize see across the entire cluster?
Get all resource recommendations.
```

### Sample Response

The response mirrors the Kruize `/listRecommendations` API format — a list of experiments, each containing Kubernetes objects with per-container recommendation data:

```json
[
  {
    "cluster_name": "default",
    "experiment_type": "container",
    "kubernetes_objects": [
      {
        "type": "deployment",
        "name": "my-app",
        "namespace": "production",
        "containers": [
          {
            "container_name": "app",
            "recommendations": {
              "version": "1.0",
              "notifications": { "111000": { "type": "info", "message": "Recommendations Are Available" } },
              "data": {
                "2026-06-18T05:11:06.000Z": {
                  "current": {
                    "requests": { "cpu": { "amount": 0.5, "format": "cores" } }
                  },
                  "recommendation_terms": { "short_term": { ... }, "medium_term": { ... } }
                }
              }
            }
          }
        ]
      }
    ]
  }
]
```

### Notes

- This can return a large payload on clusters with many workloads.
- For targeted queries, prefer `getCostOptimizedRecommendations` or `getPerformanceOptimizedRecommendations`.

---

## getCostOptimizedRecommendations

Returns cost-focused sizing recommendations (CPU requests/limits, memory requests/limits) for a specific container. Optionally filtered by namespace.

Kruize's cost engine targets reducing over-provisioned resources while staying within safe operating bounds.

### Parameters

| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `containerName` | **Yes** | string | Exact container name to look up |
| `namespace` | No | string | Restrict results to a specific namespace. Omit to search all namespaces. |

### Example Prompts

```
Get cost recommendations for the container named "app".
What are the cost-optimized recommendations for "nginx" in the "production" namespace?
How can I reduce resource costs for the "api-server" container?
Show cost savings for container "auth-cache" in namespace "app-agent".
```

### Sample Response

```json
[
  {
    "namespace": "production",
    "containerName": "app",
    "experimentName": "my-app-experiment",
    "experimentType": "container",
    "notifications": {
      "111000": { "type": "info", "message": "Recommendations Are Available" }
    },
    "currentUsage": {
      "requests": {
        "cpu": { "amount": 0.5, "format": "cores" },
        "memory": { "amount": 536870912, "format": "bytes" }
      }
    },
    "costRecommendations": [
      {
        "term": "short_term",
        "durationInHours": 24.0,
        "config": {
          "requests": {
            "cpu": { "amount": 0.12, "format": "cores" },
            "memory": { "amount": 209715200, "format": "bytes" }
          },
          "limits": {
            "cpu": { "amount": 0.12, "format": "cores" },
            "memory": { "amount": 209715200, "format": "bytes" }
          }
        },
        "variation": {
          "requests": {
            "cpu": { "amount": -0.38, "format": "cores" },
            "memory": { "amount": -327155712, "format": "bytes" }
          }
        }
      }
    ]
  }
]
```

### Notes

- `containerName` must match exactly — it is case-sensitive.
- The `variation` field shows the delta from current usage (negative = decrease).
- `short_term` covers the last 24 hours; `medium_term` covers the last 7 days.
- Returns a `message` object when no match is found.

---

## getPerformanceOptimizedRecommendations

Returns performance-focused sizing recommendations for a specific container. Optionally filtered by namespace.

Kruize's performance engine targets ensuring the workload has enough resources to avoid throttling and OOM events under peak load.

### Parameters

| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `containerName` | **Yes** | string | Exact container name to look up |
| `namespace` | No | string | Restrict results to a specific namespace. Omit to search all namespaces. |

### Example Prompts

```
Get performance recommendations for container "api-server".
What should I set CPU limits to for "nginx" in "staging" to avoid throttling?
Show performance-optimized sizing for the "worker" container.
```

### Sample Response

```json
[
  {
    "namespace": "production",
    "containerName": "api-server",
    "experimentName": "api-experiment",
    "performanceRecommendations": [
      {
        "term": "medium_term",
        "durationInHours": 168.0,
        "config": {
          "requests": {
            "cpu": { "amount": 1.0, "format": "cores" },
            "memory": { "amount": 1073741824, "format": "bytes" }
          },
          "limits": {
            "cpu": { "amount": 2.0, "format": "cores" },
            "memory": { "amount": 2147483648, "format": "bytes" }
          }
        }
      }
    ]
  }
]
```

### Notes

- Performance recommendations typically suggest **higher** values than cost recommendations.
- Use `medium_term` or `long_term` recommendations for stable production workloads.

---

## getIdleWorkloads

Returns workloads where CPU usage is effectively zero (below 1 millicore). These are candidates for scale-down or removal. Optionally includes cost and performance recommendations for each idle workload.

Idle detection is based on Kruize notification code `323001`.

### Parameters

| Parameter | Required | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `includeRecommendations` | No | boolean | `false` | When `true`, includes cost and performance recommendations alongside each idle workload |

### Example Prompts

```
Show me idle workloads.
Which workloads are consuming near-zero CPU?
List idle workloads with cost-saving recommendations.
Find workloads that can be scaled down.
Are there any abandoned deployments in the cluster?
```

### Sample Response — Summary Mode (`includeRecommendations: false`)

```json
[
  {
    "namespace": "staging",
    "containerName": "old-batch-job",
    "workloadName": "batch-processor",
    "workloadType": "deployment",
    "experimentName": "batch-experiment"
  }
]
```

### Sample Response — Detailed Mode (`includeRecommendations: true`)

```json
[
  {
    "namespace": "staging",
    "containerName": "old-batch-job",
    "workloadName": "batch-processor",
    "workloadType": "deployment",
    "experimentName": "batch-experiment",
    "currentUsage": {
      "requests": {
        "cpu": { "amount": 0.0005, "format": "cores" },
        "memory": { "amount": 52428800, "format": "bytes" }
      }
    },
    "costRecommendations": [
      {
        "term": "short_term",
        "config": {
          "requests": { "cpu": { "amount": 0.001, "format": "cores" } }
        }
      }
    ]
  }
]
```

### Notes

- Returns `[]` when no idle workloads are found.
- An idle workload is not necessarily broken — it may be a cron job awaiting its next schedule, or a standby service.
- Use `includeRecommendations: true` to get actionable sizing data for right-sizing before scale-down.

---

## Notification Codes Reference

Kruize embeds notification codes in recommendation responses. Common codes you may see:

| Code | Severity | Meaning |
|------|----------|---------|
| `111000` | Info | Recommendations are available |
| `111101` | Info | Short-term recommendations available |
| `111102` | Info | Medium-term recommendations available |
| `112101` | Info | Cost recommendations available |
| `112102` | Info | Performance recommendations available |
| `323001` | Notice | Workload is idle (CPU < 1 millicore) |
| `423001` | Warning | CPU limit not set |
| `524002` | Critical | Memory limit not set |
| `223001` | Error | CPU amount field missing |
| `224001` | Error | Memory amount field missing |

---

## Recommendation Terms

Each recommendation is scoped to a time window:

| Term | Duration | Best for |
|------|----------|----------|
| `short_term` | Last 24 hours | Rapidly changing workloads |
| `medium_term` | Last 7 days | Typical production workloads |
| `long_term` | Last 15 days | Stable, predictable workloads |

Use `medium_term` as a starting point for most production rightsizing decisions.
