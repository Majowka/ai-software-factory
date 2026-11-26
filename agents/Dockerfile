# Agent image for the pipelines: OpenCode and Claude Code, gh, JDK, Maven, Python 3.13 + uv, Go, language servers,
# skaffold and kubectl.
# One image for every repository the factory works on (Java/Maven, Python, Go, Node).
# Built and pushed to ghcr.io/majowka/factory-agent by .github/workflows/agent-image.yml.

# Go: the minor version of Majowka/mesh-manager bridge-go/go.mod; the newest patch comes with every build.
# A go.mod that needs a newer Go downloads that toolchain itself (GOTOOLCHAIN=auto).
ARG GO_VERSION=1.27
ARG UV_VERSION=0.11.32
FROM docker.io/library/golang:${GO_VERSION} AS go
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM registry.access.redhat.com/ubi9/nodejs-22

USER 0

# gcc and glibc-devel: cgo for `go test -race` (verify of Majowka/mesh-manager bridge-go)
RUN dnf install -y git jq tar gzip gcc glibc-devel \
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

# Go
COPY --from=go /usr/local/go /usr/local/go
ENV GOTOOLCHAIN=auto
ENV PATH="/usr/local/go/bin:${PATH}"

# golangci-lint, the version Majowka/mesh-manager pins in .github/workflows/bridge-go.yml (verify gate `go`)
ARG GOLANGCI_LINT_VERSION=2.15.0
RUN curl -fsSL \
    "https://github.com/golangci/golangci-lint/releases/download/v${GOLANGCI_LINT_VERSION}/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=1 "golangci-lint-${GOLANGCI_LINT_VERSION}-linux-amd64/golangci-lint" \
    && golangci-lint version

# uv and Python 3.13 (python-build-standalone). python, python3 and python3.13 in /usr/local/bin point to it;
# dnf keeps using the system /usr/bin/python3. Caches (uv, pip, Go) go to $HOME, which the tasks set to the workspace.
COPY --from=uv /uv /uvx /usr/local/bin/
ARG PYTHON_VERSION=3.13
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_LINK_MODE=copy
RUN uv python install "${PYTHON_VERSION}" --default \
    && chmod -R a+rX /opt/uv \
    && python3 --version && uv --version && go version

# Language servers, so OpenCode's lsp tool can jump to definitions and references instead of grepping:
# pyright (Python), gopls (Go), typescript-language-server (TS/JS; uses the tsserver from the project's node_modules).
# OpenCode finds them on PATH; downloads at run time are off (OPENCODE_DISABLE_LSP_DOWNLOAD).
ARG PYRIGHT_VERSION=1.1.414
ARG TS_LANGUAGE_SERVER_VERSION=6.1.0
ARG GOPLS_VERSION=0.24.0
RUN npm install -g "pyright@${PYRIGHT_VERSION}" "typescript-language-server@${TS_LANGUAGE_SERVER_VERSION}" \
    && npm cache clean --force \
    && GOBIN=/usr/local/bin GOPATH=/tmp/gopath GOCACHE=/tmp/gocache go install "golang.org/x/tools/gopls@v${GOPLS_VERSION}" \
    && rm -rf /tmp/gopath /tmp/gocache \
    && command -v pyright-langserver && gopls version && typescript-language-server --version
ENV OPENCODE_EXPERIMENTAL_LSP_TOOL=true \
    OPENCODE_DISABLE_LSP_DOWNLOAD=true

USER 1001
