# Migracja: OpenShift → k3s/Kubernetes, bez vLLM/GPU

Lista zadań dla gałęzi `claude/project-thread-cvdyq6`. Kolejność = kolejność pracy.

## Do decyzji

- [x] **Silnik agenta**: oba, OpenCode (OpenCode Go) i Claude Code (OAuth), z wyborem per zadanie.
- [x] Wejście webhooka: App `KlaudiuszAI` (jeden URL dla orga) → Worker `github-openbot-relay`, trasa `factory` (Majowka/infrastructure#1945) → Workers VPC `ai-factory-el` → `cloudflared` w k3s (Majowka/gitops#180). Klaster bez publicznego wejścia.
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
- [x] Wybór silnika etykietą na issue/PR: `engine:<silnik>` lub `engine-<zadanie>:<silnik>`, nadpisuje `routing.env`; zadania z requirements dziedziczą etykiety.
- [ ] Założyć etykiety `engine:claude`, `engine:opencode` (i ewentualnie `engine-<zadanie>:...`) w repozytoriach, które obsługuje fabryka.
- [ ] Opcjonalnie: subagenci OpenCode przetłumaczeni na format Claude Code.

## 3. Manifesty pod k3s (`deploy/k3s`, `deploy/openshift`, wspólne `agents/` i `tekton/`)

- [x] Ingress niepotrzebny na naszym k3s (webhook przez Workers VPC); `deploy/k3s/ingress-new-issue.yaml` zostaje jako opcja dla innych klastrów.

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
- [x] Tunel `k3s-ai-factory` i VPC Service `ai-factory-el` założone przez API CF; token tunelu w Infisical (`infra-k3s` / `vrtx-cluster`).
- [ ] Token deployu Workera: dodać Connectivity Directory: Bind.
- [ ] Po deployu Workera: `FACTORY_REPO_IDS`, `FACTORY_ROUTE_ENABLED=true`; Secrety `cloudflared-tunnel` i `github-webhook-secret` (= sekret webhooka App) w `ai-factory`.
- [ ] Login bota w CEL i `GIT_AUTHOR_*` → `klaudiuszai[bot]`.

## 5. Dokumentacja

- [x] README: `oc` → `kubectl`, `oc new-project` → `kubectl create ns`, `oc secrets link` → `kubectl patch sa`.
- [x] `install/README.md`: oznaczony jako log klastra ROSA; instrukcja k3s w `deploy/k3s/README.md` i README (sekcje 1, 6.2).
- [x] Opisy w README: Ingress/Route, dwa silniki, bez vLLM; skrócone kopie YAML zastąpione odnośnikami do plików.
- [ ] Diagramy SVG (`docs/diagrams`, `docs/images/factory-overview.svg`) nadal pokazują vLLM/OpenShift — do przerysowania.

## 6. Test end-to-end

- [ ] Nowe issue → PipelineRun → PR w repo testowym.
- [ ] Komentarz do issue i do PR, CronJob `requirements-scan`.
