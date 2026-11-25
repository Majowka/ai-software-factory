# Migracja: OpenShift → k3s/Kubernetes, bez vLLM/GPU

Lista zadań dla gałęzi `claude/project-thread-cvdyq6`. Kolejność = kolejność pracy.

## Do decyzji

- [ ] **Silnik agenta**: (A) zostaje OpenCode, zmienia się tylko provider (OpenCode Go i/lub Anthropic) — zalecane, mały zakres; (B) Claude Code CLI zamiast OpenCode — średni zakres (kroki Tekton, uprawnienia, obraz).
- [ ] Publiczne wejście dla webhooka GitHuba na k3s (Traefik ma tylko prywatne IP): BunkerWeb, Tailscale Funnel lub inny reverse proxy.
- [ ] Rejestr obrazu agenta (dziś `quay.io/pminkows/opencode:latest`): własny tag na Quay/GHCR.

## 1. Usunięcie vLLM / GPU

- [x] Usunąć `ai/` (Deploymenty i Service `qwen38-flash`, `qwen3-coder`, PVC cache).
- [x] Usunąć `secrets/secret-hf-token.yaml`.
- [x] README: usunąć sekcje o GPU, NFD, NVIDIA GPU Operator, modelu i namespace `ai`.

## 2. Zewnętrzny model (wariant A — OpenCode)

- [ ] `agents/configmap-agent-config.yaml`: w `opencode.json`, `opencode-requirements.json`, `opencode-plan.json` zamienić `model` i `provider` (zamiast `qwen38-flash.ai.svc.cluster.local`) na OpenCode Go / `anthropic` — nazwy providera i ID modeli potwierdzić w dokumentacji OpenCode Go.
- [ ] Secret z kluczem API (`OPENCODE_API_KEY` / `ANTHROPIC_API_KEY`), bez wartości w repo.
- [ ] Podpiąć klucz przez `env` w krokach agenta: `pipeline-issue-agent.yaml`, `pipeline-issue-comment-agent.yaml`, `pipeline-pr-comment-agent.yaml`, `pipeline-requirements-agent.yaml`, `task-verify-build.yaml`.

## 2b. Wariant B — Claude Code CLI (tylko jeśli wybrany)

- [ ] `agents/Dockerfile`: dodać JDK i Maven (jak w `Dockerfile.opencode`), zbudować i wypchnąć obraz.
- [ ] Zamienić 8 wywołań `opencode run` na `claude -p` w 5 plikach Tekton.
- [ ] Przenieść uprawnienia z `opencode*.json` do `settings.json` Claude Code (`permissions.allow/deny`), skille do `~/.claude/skills`.
- [ ] Uwierzytelnianie kluczem API (`ANTHROPIC_API_KEY`), nie subskrypcją.

## 3. Manifesty pod k3s

- [ ] `tekton/route-new-issue.yaml` → `Ingress` (Traefik) z TLS (cert-manager lub cert z zewnętrznego proxy).
- [ ] Dodać ServiceAccount `pipeline` (+ RoleBinding), na OpenShift tworzy go operator Pipelines.
- [ ] `triggertemplate-new-issue.yaml`: jawny `taskRunTemplate.serviceAccountName: pipeline` (jak w pozostałych).
- [ ] Workspace'y Tekton: działają na domyślnym StorageClass (`local-path`); ewentualnie `podTemplate.securityContext.fsGroup`.
- [ ] Kustomization dla całości (`kubectl apply -k`), opcjonalnie overlaye `openshift/` i `k3s/`.

## 4. Platforma (repo `infrastructure` / `Majowka/gitops`)

- [ ] Tekton Pipelines + Triggers + Interceptors jako aplikacja ArgoCD.
- [ ] `feature-flags` w `tekton-pipelines`: `coschedule: disabled` (zamiast `oc patch tektonconfig`).
- [ ] Namespace `agents`, Secrety (GitHub App, webhook secret, klucz API) — docelowo przez ESO/Infisical.
- [ ] Ruch wychodzący z podów do GitHub i API modeli.
- [ ] Publiczny URL webhooka + aktualizacja w GitHub App.

## 5. Dokumentacja

- [ ] README: `oc` → `kubectl`, `oc new-project` → `kubectl create ns`, `oc secrets link` → `kubectl patch sa`.
- [ ] `install/README.md`: zastąpić instalację ROSA instrukcją dla k3s.
- [ ] Diagramy/opisy: „OpenShift Route” → Ingress, bez vLLM.

## 6. Test end-to-end

- [ ] Nowe issue → PipelineRun → PR w repo testowym.
- [ ] Komentarz do issue i do PR, CronJob `requirements-scan`.
