# Agent image for the pipelines: OpenCode and Claude Code, gh, JDK, Maven, skaffold and kubectl.
# Built and pushed to ghcr.io/majowka/factory-agent by .github/workflows/agent-image.yml.
FROM registry.access.redhat.com/ubi9/nodejs-22

USER 0

RUN dnf install -y git jq tar gzip \
    && dnf clean all

# Both agent engines; agent-run.sh (ConfigMap agent-config) picks one per task
RUN npm install -g opencode-ai @anthropic-ai/claude-code

# GitHub CLI z oficjalnego archiwum
ARG GH_VERSION=2.83.2
RUN curl -fsSL \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    -o /tmp/gh.tar.gz \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && cp /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/gh \
    && rm -rf /tmp/gh*

# Skaffold (build i deployment aplikacji na Kubernetes)
ARG SKAFFOLD_VERSION=2.25.0
RUN curl -fsSL \
    "https://storage.googleapis.com/skaffold/releases/v${SKAFFOLD_VERSION}/skaffold-linux-amd64" \
    -o /usr/local/bin/skaffold \
    && chmod +x /usr/local/bin/skaffold

# kubectl (z niego korzysta skaffold przy deploymencie)
ARG KUBECTL_VERSION=1.37.2
RUN curl -fsSL \
    "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# OpenJDK 25 (Eclipse Temurin)
RUN mkdir -p /opt/java \
    && curl -fsSL \
    "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse" \
    | tar -xz -C /opt/java --strip-components=1
ENV JAVA_HOME=/opt/java

# Maven z Maven Central
ARG MAVEN_VERSION=3.9.11
RUN mkdir -p /opt/maven \
    && curl -fsSL \
    "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    | tar -xz -C /opt/maven --strip-components=1
ENV MAVEN_HOME=/opt/maven
ENV PATH="${JAVA_HOME}/bin:${MAVEN_HOME}/bin:${PATH}"

USER 1001
