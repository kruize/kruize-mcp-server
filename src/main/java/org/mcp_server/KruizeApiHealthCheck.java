package org.mcp_server;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.ProcessingException;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Readiness;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Readiness health check for Kruize API connectivity.
 * This check verifies that the Kruize backend API is accessible and responding
 * using the /health endpoint.
 *
 * When this check fails:
 * - The pod is marked as NOT READY
 * - Kubernetes removes the pod from service endpoints
 * - No traffic is routed to this pod
 * - The pod is NOT restarted (unlike liveness probe failures)
 *
 * This ensures zero-downtime deployments and graceful handling of backend issues.
 */
@Readiness
@ApplicationScoped
public class KruizeApiHealthCheck implements HealthCheck {
    private static final Logger log = LoggerFactory.getLogger(KruizeApiHealthCheck.class);

    @Inject
    @RestClient
    KruizeApiClient apiClient;

    @Override
    public HealthCheckResponse call() {
        try {
            long startTime = System.currentTimeMillis();
            
            // Check /health endpoint
            apiClient.getHealth();
            
            long responseTime = System.currentTimeMillis() - startTime;
            
            log.debug("Kruize API health check passed in {}ms", responseTime);
            
            return HealthCheckResponse.named("Kruize API")
                    .up()
                    .withData("responseTimeMs", responseTime)
                    .build();
                    
        } catch (WebApplicationException e) {
            // HTTP-level errors (4xx, 5xx responses)
            Response response = e.getResponse();
            int statusCode = response.getStatus();
            String statusInfo = response.getStatusInfo().getReasonPhrase();
            
            log.warn("Kruize API health check failed with HTTP {}: {}", statusCode, statusInfo);
            
            return HealthCheckResponse.named("Kruize API")
                    .down()
                    .withData("error", "HTTP error")
                    .withData("statusCode", statusCode)
                    .withData("statusMessage", statusInfo)
                    .build();
                    
        } catch (ProcessingException e) {
            // Connection/network errors (timeouts, connection refused, etc.)
            String errorType = "Connection error";
            String errorMessage = e.getMessage();
            
            // Identify specific connection issues by checking the exception message and cause
            Throwable cause = e.getCause();
            if (cause != null) {
                if (cause instanceof java.net.ConnectException) {
                    errorType = "Connection refused";
                } else if (cause instanceof java.net.SocketTimeoutException) {
                    errorType = "Connection timeout";
                } else if (cause instanceof java.net.UnknownHostException) {
                    errorType = "Unknown host";
                }
            }
            
            // Check for Netty ConnectTimeoutException in the message
            if (errorMessage != null && errorMessage.contains("ConnectTimeoutException")) {
                errorType = "Connection timeout";
            }
            
            log.warn("Kruize API health check failed: {} - {}", errorType, errorMessage);
            
            return HealthCheckResponse.named("Kruize API")
                    .down()
                    .withData("error", errorType)
                    .withData("details", errorMessage)
                    .build();
                    
        } catch (Exception e) {
            // Catch-all for unexpected errors
            log.warn("Kruize API health check failed with unexpected error: {}", e.getMessage());
            
            return HealthCheckResponse.named("Kruize API")
                    .down()
                    .withData("error", "Unexpected error")
                    .withData("type", e.getClass().getSimpleName())
                    .withData("message", e.getMessage())
                    .build();
        }
    }
}
