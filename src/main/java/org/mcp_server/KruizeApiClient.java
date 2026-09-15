package org.mcp_server;

import jakarta.ws.rs.QueryParam;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import java.util.List;
import org.mcp_server.ExperimentApiResponseRecords.Experiment;
import org.mcp_server.RecommendationApiResponseRecords.*;

@RegisterRestClient
public interface KruizeApiClient {

    @GET
    @Path("/listExperiments")
    List<Experiment> getAllExperiments();

    @GET
    @Path("/listRecommendations")
    List<Recommendations> getAllRecommendations();

    @GET
    @Path("/health")
    String getHealth();
}