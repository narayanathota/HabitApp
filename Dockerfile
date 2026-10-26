# syntax=docker/dockerfile:1

# ---- Stage 1: build the jar with Maven + JDK 21 ----
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace

# Copy only pom.xml first so the dependency layer is cached until the pom changes
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
# Tests already ran in the Jenkins "Unit Test" stage, so skip them here
RUN mvn -B -q clean package -DskipTests

# ---- Stage 2: small runtime image (JRE only) ----
FROM eclipse-temurin:21-jre-alpine

# Dedicated non-root user with a fixed numeric UID/GID (Kubernetes runAsNonRoot needs numeric)
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app -H -s /sbin/nologin app

WORKDIR /app
COPY --from=build --chown=10001:10001 /workspace/target/habit-tracker.jar app.jar

USER 10001:10001
EXPOSE 8080

# Container-aware heap sizing; override at runtime if needed
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0"

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:8080/actuator/health | grep -q '"status":"UP"' || exit 1

# exec so the JVM is PID 1 and receives SIGTERM for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
