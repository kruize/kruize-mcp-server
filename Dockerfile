# ---- Build stage ----
# Red Hat UBI9 OpenJDK 21 image defaults to non-root uid 185 (default:root);
# /deployments is pre-created and owned by that user, so no privilege escalation needed.
FROM registry.access.redhat.com/ubi9/openjdk-21:1.24-3.1788862457 AS build

COPY pom.xml /deployments/pom.xml
COPY src /deployments/src
RUN mvn -f /deployments/pom.xml -B clean package

# ---- Runtime stage ----
# Minimal Red Hat UBI9 JRE image; runs as non-root user 185 by default
FROM registry.access.redhat.com/ubi9/openjdk-21-runtime:1.24-3.1788862450

WORKDIR /deployments

# Copy the executable JAR from the build stage
COPY --from=build /deployments/target/*-runner.jar /deployments/app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/deployments/app.jar"]
