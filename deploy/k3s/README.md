# Running the factory on k3s / upstream Kubernetes

Differences from OpenShift and what this overlay does about them:

| OpenShift | k3s / upstream | Where |
|---|---|---|
| OpenShift Pipelines operator | Tekton Pipelines, Triggers and Interceptors from the upstream releases (or Helm / ArgoCD) | cluster setup |
| `oc patch tektonconfig ... coschedule: disabled` | `kubectl patch cm feature-flags -n tekton-pipelines --type merge -p '{"data":{"coschedule":"disabled"}}'` | cluster setup |
| `pipeline` service account created by the operator | `serviceaccount-pipeline.yaml` | this overlay |
| Route with edge TLS | Traefik `Ingress` (`ingress-new-issue.yaml`), set the host and TLS | this overlay |
| `oc new-project agents` | `namespace.yaml` | this overlay |
| `oc secrets link pipeline <secret> --for=pull` | `imagePullSecrets` in `serviceaccount-pipeline.yaml` | this overlay |
| default StorageClass `gp3-csi` | any default RWO class; k3s ships `local-path` | nothing to change |

## Install

```bash
# 1. Tekton (pin versions that match each other)
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
kubectl patch cm feature-flags -n tekton-pipelines --type merge -p '{"data":{"coschedule":"disabled"}}'
kubectl get clusterinterceptors          # github, cel, ...

# 2. The factory (set the Ingress host first)
kubectl apply -k deploy/k3s

# 3. Secrets (top-level README, section 3): github-app, github-webhook-secret, opencode-go, claude-code-oauth
```

Then point the GitHub App webhook at `https://<ingress host>` (top-level README, section 7).

Pods in `agents` need outbound HTTPS to `github.com`, `api.github.com`, `ghcr.io`, `quay.io` (skills artifact),
`opencode.ai` and `api.anthropic.com`.
