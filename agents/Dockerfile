FROM registry.access.redhat.com/ubi9/nodejs-22

USER 0

RUN dnf install -y git jq tar gzip \
    && dnf clean all

RUN npm install -g @anthropic-ai/claude-code

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

USER 1001
