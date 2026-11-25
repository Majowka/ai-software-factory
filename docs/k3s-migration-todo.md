# Migracja: OpenShift → k3s/Kubernetes, bez vLLM/GPU

Lista zadań dla gałęzi `claude/project-thread-cvdyq6`. Kolejność = kolejność pracy.

## Do decyzji

- [x] **Silnik agenta**: oba, OpenCode (OpenCode Go) i Claude Code (OAuth), z wyborem per zadanie.
- [ ] Publiczne wejście dla webhooka GitHuba na k3s (Traefik ma tylko prywatne IP): BunkerWeb, Tailscale Funnel lub inny reverse proxy.
- [x] Rejestr obrazu agenta: `ghcr.io/majowka/factory-agent` (pakiet GHCR może wymagać pull secretu, jeśli prywatny).

## 1. Usunięcie vLLM / GPU

- [x] Usunąć `ai/` (Deploymenty i Service `qwen38-flash`, `qwen3-coder`, PVC cache).
- [x] Usunąć `secrets/secret-hf-token.yaml`.
- [x] README: usunąć sekcje o GPU, NFD, NVIDIA GPU Operator, modelu i namespace `ai`.

## 2. Dwa silniki z routingiem per zadanie (decyzja: OpenCode + OpenCode Go i Claude Code z OAuth)

- [x] `routing.env` w `agent-config`: silnik i model dla zadań PLAN, IMPLEMENT, FIX, REQUIREMENTS.
- [x] `agent-run.sh`: jedno wejście dla obu silników (`opencode run` / `claude -p`), wołane we wszystkich 8 miejscach.
- [x] `opencode.json` z providerem `opencode-go` (klucz z `OPENCODE_API_KEY`); usunięte `opencode-plan.json` i `opencode-requirements.json`.
- [x] `claude-settings.json` z tymi samymi zakazami (git commit/push, gh, web).
- [x] Kroki `plan` nie dostają już tokenu GitHub: plan publikuje skrypt, nie agent (działa tak samo dla obu silników).
- [x] Skille instalowane dla obu silników (`agent-home.sh`); subagenci OpenCode tylko dla OpenCode.
- [x] Jeden obraz `agents/Dockerfile` z OpenCode i Claude Code, build do `ghcr.io/majowka/factory-agent` przez GitHub Actions.
- [x] Szkielety sekretów `opencode-go` i `claude-code-oauth`.
- [ ] Sprawdzić na żywo: `{env:OPENCODE_API_KEY}` w `opencode.json`, lista modeli OpenCode Go, `claude -p` z tokenem OAuth.
- [ ] Opcjonalnie: wybór silnika per issue etykietą (np. `engine:claude`), nadpisujący `routing.env`.
- [ ] Opcjonalnie: subagenci OpenCode przetłumaczeni na format Claude Code.

## 3. Manifesty pod k3s (`deploy/k3s`, `deploy/openshift`, wspólne `agents/` i `tekton/`)

- [ ] Ustawić host w `deploy/k3s/ingress-new-issue.yaml` i źródło certyfikatu TLS.

- [x] `tekton/route-new-issue.yaml` → `Ingress` (Traefik) z TLS (cert-manager lub cert z zewnętrznego proxy).
- [x] Dodać ServiceAccount `pipeline` (+ RoleBinding), na OpenShift tworzy go operator Pipelines.
- [x] `triggertemplate-new-issue.yaml`: jawny `taskRunTemplate.serviceAccountName: pipeline` (jak w pozostałych).
- [x] Workspace'y Tekton: działają na domyślnym StorageClass (`local-path`); ewentualnie `podTemplate.securityContext.fsGroup`.
- [x] Kustomization dla całości (`kubectl apply -k`), opcjonalnie overlaye `openshift/` i `k3s/`.

## 4. Platforma (repo `infrastructure` / `Majowka/gitops`)

- [ ] Tekton Pipelines + Triggers + Interceptors jako aplikacja ArgoCD.
- [ ] `feature-flags` w `tekton-pipelines`: `coschedule: disabled` (zamiast `oc patch tektonconfig`).
- [ ] Namespace `agents`, Secrety (GitHub App, webhook secret, klucz API) — docelowo przez ESO/Infisical.
- [ ] Ruch wychodzący z podów do GitHub, GHCR, Quay i API modeli (`opencode.ai`, `api.anthropic.com`).
- [ ] Publiczny URL webhooka + aktualizacja w GitHub App.

## 5. Dokumentacja

- [ ] README: `oc` → `kubectl`, `oc new-project` → `kubectl create ns`, `oc secrets link` → `kubectl patch sa`.
- [ ] `install/README.md`: zastąpić instalację ROSA instrukcją dla k3s.
- [ ] Diagramy/opisy: „OpenShift Route” → Ingress, bez vLLM.

## 6. Test end-to-end

- [ ] Nowe issue → PipelineRun → PR w repo testowym.
- [ ] Komentarz do issue i do PR, CronJob `requirements-scan`.
