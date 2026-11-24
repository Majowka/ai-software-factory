# Plan: test cluster for the AI Software Factory (ROSA + 1 GPU node)

This file is the plan for the agent (Claude Code) that builds the test cluster, so the user does not have to explain it again.
Read it completely before touching AWS or the cluster. It is a description, not automation: check the CLI flags with `--help`
before use (the commands are the intended shape) and update this file when reality differs.

The factory itself is described in the top-level `README.md`. This file covers only the cluster and its operators.

## What the user asked for

- A ROSA cluster on an AWS account the user hands over. **First check the preconditions** and say what has to be done manually.
- One GPU node, preferably **`g7e.12xlarge`** (2x NVIDIA RTX PRO 6000 Blackwell, 96 GB each, 48 vCPU, 512 GiB RAM, 3.8 TB NVMe).
  This fits the model manifests in `ai/` (2 GPUs per deployment, 180-200 GiB memory).
- **Choose the region first**: one that has quota for that node.
- Find **all AZs** that offer the instance type and create a machine pool in each, but **only one pool with replicas 1**, the others 0.
- Install the **Node Feature Discovery Operator** and the **NVIDIA GPU Operator**, and create the one required custom resource of each.
- Install **Red Hat OpenShift Pipelines**.
- Namespaces: **`ai`** (models) and **`agents`** (pipelines).
- Purpose: test the factory end to end, including the requirements agent (README section 6.9).

## Rules

1. **Ask the user before every command that creates, changes or deletes AWS or cluster resources.** The GPU node is expensive and ROSA bills hourly.
   Read-only checks need no confirmation.
2. Never write passwords, tokens, kubeadmin/admin credentials or the GitHub App key into the repo or a commit. Show a one-time password in the
   terminal and tell the user to store it.
3. Confirm with the user that the AWS account in `aws sts get-caller-identity` is the intended one before creating anything.
4. Use `! <command>` (the user types it in the prompt) for interactive logins such as `rosa login --use-auth-code` or `aws configure sso`.
5. Log decisions and results in the *Run log* at the end of this file. Offer to scale the GPU pool to 0 at the end of every session.

## Status

Update as you go.

- [x] Phase 0: preconditions checked, manual steps done by the user
- [x] Phase 1: region chosen (eu-central-1, AZs a and b)
- [x] Phase 2: ROSA HCP cluster created and reachable with `oc` (cluster `factory-east`, us-east-2)
- [x] Phase 3: GPU machine pools in every AZ, one node running (gpu-c, us-east-2c)
- [x] Phase 4: operators and custom resources installed
- [ ] Phase 5: verified (done), factory objects deployed (README sections 2-7, not yet)

## Phase 0: preconditions

Run the read-only checks and give the user a table (OK / missing / needs you).

| Check | Command | If it fails |
|---|---|---|
| Tools | `aws --version; rosa version; oc version --client; jq --version` | user installs (`brew install awscli rosa-cli openshift-cli jq`) |
| AWS identity | `aws sts get-caller-identity` | **user:** configure credentials (`! aws configure sso` or `AWS_*` variables) |
| Red Hat login | `rosa whoami` | **user:** `! rosa login --use-auth-code` (needs a browser) |
| ROSA enabled on the AWS account | `rosa verify quota --region <r>` and its prerequisites message | **user:** enable ROSA in the AWS console, link the Red Hat account |
| IAM permissions | `rosa verify permissions` | **user:** attach the missing permissions (admin is simplest on a test account) |
| ELB service-linked role | `aws iam get-role --role-name AWSServiceRoleForElasticLoadBalancing` | `aws iam create-service-linked-role --aws-service-name elasticloadbalancing.amazonaws.com` (ask first) |
| Billing account for HCP | `rosa create cluster --help` shows `--billing-account` | **user:** link an AWS billing account to the ROSA subscription in the Red Hat console |
| Leftovers | `rosa list clusters; rosa list account-roles; rosa list oidc-config` | reuse matching account roles and OIDC config, otherwise ask |

Also ask for: cluster name, public or private cluster (default for a test: public), OpenShift version (default: the newest that
`rosa list versions --hosted-cp` offers and the GPU Operator supports).

## Phase 1: region

Needed in the region: (a) `g7e.12xlarge` offered in at least one AZ, (b) enough quota, (c) ROSA HCP support (`rosa list regions --hosted-cp`).

- Quota: **"Running On-Demand G and VT instances"**, code `L-DB2E81BA`, counted in **vCPUs**, default often 0. One `g7e.12xlarge` = 48 vCPU.
  With one GPU node running and the others at 0, 48 is enough (scale the old pool to 0 before scaling another to 1); ask for 96 for headroom.
  The ordinary workers use a different quota.
- Regions where g7e was announced (AWS, up to July 2026): us-east-1, us-east-2, us-west-2, eu-south-2 (Spain), eu-west-2 (London),
  eu-central-1 (Frankfurt), eu-north-1 (Stockholm), ap-northeast-1 (Tokyo), ap-northeast-2 (Seoul), ap-south-1 (Mumbai).
  This is a candidate list only: that the family is offered does not prove the `12xlarge` size is, and the list grows.
  The user is in Europe: Frankfurt, Stockholm, Spain and London are the natural picks.

```bash
for r in us-east-1 us-east-2 us-west-2 eu-south-2 eu-west-2 eu-central-1 eu-north-1 ap-northeast-1 ap-northeast-2 ap-south-1; do
  azs=$(aws ec2 describe-instance-type-offerings --region $r --location-type availability-zone \
        --filters Name=instance-type,Values=g7e.12xlarge --query 'InstanceTypeOfferings[].Location' --output text 2>/dev/null)
  quota=$(aws service-quotas get-service-quota --region $r --service-code ec2 --quota-code L-DB2E81BA \
        --query 'Quota.Value' --output text 2>/dev/null)
  echo "$r quota=${quota:-n/a} azs=[$azs]"
done
```

Choose: quota >= 48 and at least one AZ; more AZs is better (more chances for capacity). Present the table and a recommendation; the **user decides**.

If no region has quota: **user** requests an increase of `L-DB2E81BA` (Service Quotas console, in the target region). It can take hours or days; stop and wait.
Quota does not guarantee capacity: a launch can still fail with `InsufficientInstanceCapacity`, which is why Phase 3 prepares a pool in every AZ.

## Phase 2: cluster (ROSA with hosted control planes)

Use **HCP**, not classic: an HCP machine pool lives in exactly one subnet, so one AZ, which is what the per-AZ GPU pools need.

1. **Network.** A VPC with a private subnet (plus a public one for a public cluster) in **every AZ that offers the GPU type** and in the AZs for the
   default workers. `rosa create network --help` creates one from a template, or reuse a VPC. Subnets added after cluster creation need the tag
   `kubernetes.io/cluster/<infra-id>=shared`; private subnets carry `kubernetes.io/role/internal-elb`.
2. **Roles and OIDC** (reuse when they exist): `rosa create account-roles --hosted-cp --mode auto`, `rosa create oidc-config --mode auto`.
3. **Cluster:** `rosa create cluster --cluster-name <name> --sts --hosted-cp --region <r> --subnet-ids <ids> --oidc-config-id <id> --operator-roles-prefix <p> --billing-account <acct> --compute-machine-type m5.xlarge --replicas 2`.
   HCP needs at least 2 workers in the default pool; Tekton and the listener run there, the GPU node is an addition. Watch with `rosa logs install -c <name> --watch`.
4. **Admin:** `rosa create admin -c <name>` prints a one-time password; show it to the user, do not store it. Then `oc login <api-url> --username cluster-admin`.

Done when `rosa describe cluster -c <name>` says `ready` and `oc get nodes` works.

## Phase 3: GPU machine pools

1. AZs with the GPU type: the `azs` list from Phase 1 for the chosen region. Map each AZ to the cluster's private subnet there
   (`rosa describe cluster -c <name> -o json | jq '.aws.subnet_ids'`, then `aws ec2 describe-subnets` and filter by AZ and the `internal-elb` tag).
2. One pool per AZ, all `g7e.12xlarge`, tainted so that only GPU workloads land there (the manifests in `ai/` tolerate `nvidia.com/gpu:NoSchedule`):

   ```bash
   rosa create machinepool -c <name> --name gpu-<az> --instance-type g7e.12xlarge \
     --subnet <private-subnet-of-az> --replicas 0 --taints nvidia.com/gpu=:NoSchedule
   ```

   Exactly **one** pool gets `--replicas 1` (the first AZ is fine); all others 0. Pool names are limited in length: use short names like `gpu-1a`, not `gpu-eu-central-1a`. `--replicas 0` is accepted for a new pool.
   - Red Hat constraints: a pool belongs to one subnet, at most one pool per AZ, and taints on a pool need another untainted pool (the default pool is).
   - If `--replicas 0` is rejected for a new pool, create only the active pool now and the next ones on demand (only one is ever needed).
   - Consider a larger root disk (`--disk-size`, check `--help`): the vLLM images are big.
3. **Check the taint reached the node.** Known bug OCPBUGS-31540: labels and taints set via the ROSA CLI did not sync to HCP nodes.
   `oc describe node <gpu-node> | grep -i taint`. If missing: `oc adm taint nodes <node> nvidia.com/gpu=:NoSchedule`, and tell the user it will not survive node replacement.
4. **No capacity** (`rosa describe machinepool`, machine events show `InsufficientInstanceCapacity`): `rosa edit machinepool -c <name> gpu-<az> --replicas 0`,
   then `--replicas 1` on the next AZ's pool. Repeat; tell the user which AZ worked.

Done when one node of type `g7e.12xlarge` is `Ready`. Idle: set the active pool to `--replicas 0`.

## Phase 4: operators

Install with OLM `Subscription` objects. Do not assume channels; read them from the cluster:
`oc get packagemanifest <package> -n openshift-marketplace -o jsonpath='{.status.defaultChannel}'`.

| Operator | Package, catalog | Namespace | Custom resource |
|---|---|---|---|
| Node Feature Discovery | `nfd`, `redhat-operators` | `openshift-nfd` | `NodeFeatureDiscovery` (one) |
| NVIDIA GPU Operator | `gpu-operator-certified`, `certified-operators` | `nvidia-gpu-operator` | `ClusterPolicy` (one) |
| Red Hat OpenShift Pipelines | `openshift-pipelines-operator-rh`, `redhat-operators` | `openshift-operators` (global OperatorGroup exists) | none, the operator creates `TektonConfig` |

Order: NFD, then the GPU Operator; Pipelines is independent.

For NFD and the GPU Operator: `Namespace`, an `OperatorGroup` with `targetNamespaces: [<own namespace>]`, a `Subscription`
(`name`/`channel` from the package, `source` the catalog, `sourceNamespace: openshift-marketplace`, `installPlanApproval: Automatic`).
Wait for `oc get csv -n <ns>` to show `Succeeded`, then create the custom resource from the operator's own example so the defaults match its version:

```bash
oc get csv -n <ns> -o json | jq -c --arg k NodeFeatureDiscovery \
  '.items[].metadata.annotations["alm-examples"] | fromjson | .[] | select(.kind==$k)' | oc apply -f -    # or ClusterPolicy
```

GPU specifics: Blackwell needs a recent driver and, as far as I know, the **open kernel modules**: set `spec.driver.useOpenKernelModules: true` in the
`ClusterPolicy` before applying (verify this in the GPU Operator release notes; I have not confirmed it against a source).

Then `oc new-project ai` and `oc new-project agents`.

## Phase 5: verify and hand over

```bash
oc get nodes -l feature.node.kubernetes.io/pci-10de.present=true        # the GPU node is labeled by NFD
oc get clusterpolicy -o jsonpath='{.items[0].status.state}'              # ready
oc describe node <gpu-node> | grep -A2 'nvidia.com/gpu'                  # allocatable 2, taint present
oc get csv -A | grep -E 'nfd|gpu-operator|pipelines'                     # Succeeded
oc get clusterinterceptors                                               # github and cel
oc get sc                                                                # default class (the manifests use gp3-csi)
```

Then continue with the top-level `README.md` from section 2 (GitHub App) and 3 (secrets). The **user** supplies the GitHub App, webhook secret and
Hugging Face token. The model deployments in `ai/` ship with `replicas: 0`; scale up only one (each needs both GPUs). For the requirements agent apply the
objects listed in README section 6.9.

## Capacity: test it directly before building a cluster

The reliable way to find a working AZ is to launch one instance and terminate it at once; it takes seconds and a failed launch costs nothing.
Use a temporary VPC with one subnet per AZ that offers the type (no default VPC exists on these sandbox accounts), an Amazon Linux 2023 AMI from SSM
(`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`) and `aws ec2 run-instances --instance-type g7e.12xlarge --count 1 --subnet-id <s>
--instance-initiated-shutdown-behavior terminate`, then `terminate-instances`. A g7e instance needs about 4 minutes to leave `shutting-down`, so wait before
deleting the temporary subnet and VPC. Capacity changes by the minute: build the cluster right after a successful test.

## Capacity: quota is not capacity

On 2026-11-23 in eu-central-1 (quota 768, g7e.12xlarge offered in a and b) every launch failed with `Server.InsufficientInstanceCapacity` in both AZs
and the pool stayed at 0/1 with the message "Waiting for AWSMachine to report spec.providerID". Spot Placement Score is a cheap read-only hint for where
hardware is free, use it in Phase 1 and prefer the AZs with high scores (it is a proxy for Spot, not a guarantee for on-demand):

```bash
aws ec2 get-spot-placement-scores --instance-types g7e.12xlarge --target-capacity 1 --single-availability-zone \
  --region-names us-east-1 us-east-2 us-west-2 eu-north-1 ... --region us-east-1 \
  --query 'SpotPlacementScores[].[Region,AvailabilityZoneId,Score]' --output text
```

Map AZ ids to names per account with `aws ec2 describe-availability-zones --region <r>`. To see launch failures when a pool does not come up:
`aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances` and look at `errorCode`.
The first real signal is the pool: if no node after about 5 minutes, check CloudTrail instead of waiting.

## When things go wrong

| Symptom | Likely cause and action |
|---|---|
| `rosa create cluster` complains about roles or OIDC | create or reuse account roles and an OIDC config (Phase 2.2) |
| Node never appears (pool stays 0/1), CloudTrail `InsufficientInstanceCapacity` | no g7e capacity in that AZ: switch pools (Phase 3.4) |
| Machine event about vCPU limit | GPU quota too low in the region: request an increase (Phase 1) |
| GPU node `Ready` but no `nvidia.com/gpu` | NFD label missing or the `ClusterPolicy` not ready: `oc get pods -n nvidia-gpu-operator`; check the driver pod logs (open kernel modules for Blackwell) |
| Model pod `Pending` | taint not on the node, or `nvidia.com/gpu` not allocatable, or both deployments scaled up (4 GPUs needed) |
| Pods cannot pull vLLM images | pull secret / access to `registry.redhat.io` |

## Teardown (ask first, confirm the cluster name with the user)

1. Idle only: `rosa edit machinepool -c <name> gpu-<az> --replicas 0` (the control plane and 2 workers keep billing).
2. Delete: `rosa delete cluster -c <name>`, then `rosa delete operator-roles -c <name>` and `rosa delete oidc-provider -c <name>`;
   remove the VPC created for it and leftover EBS volumes (the model cache PVC).

## Run log

| Date | What happened |
|---|---|
| 2026-11-23 | Plan written. Preflight on the user's laptop: `aws`, `rosa`, `oc`, `jq` installed; no AWS credentials configured, `rosa` not logged in, nothing created. |
| 2026-11-23 | User supplied an IAM user key (account `105455903431`, user `open-environment-txhtv-admin`, alias `sandbox532-gpte`, a sandbox account). Keys were used only as env vars in commands, never written to a file. The user was already logged in to Red Hat (OCM org `1H1PQMDtwzAUsjPxgoWRjhSpNGD`). ELB service-linked role existed. No existing clusters. |
| 2026-11-23 | Phase 1: g7e.12xlarge offered and GPU quota (L-DB2E81BA) in us-east-1 quota 4 (too low), us-east-2 768 (AZ a,b,c), us-west-2 768 (a,b,c,d), eu-west-2 768 (a,c), **eu-central-1 768 (a,b)**, eu-north-1 64 (a,c), ap-northeast-1 64 (a,c), ap-northeast-2 768, ap-south-1 768; eu-south-2 is not enabled for the account. User chose **eu-central-1**. Default HCP version: 4.22.22. |
| 2026-11-23 | Created in the account (eu-central-1): account roles with prefix `ManagedOpenShift` (HCP Installer/Support/Worker), managed OIDC config `2u96pmu3hjt9hcrt5183cefqapo0a1i4`, OCM role `ManagedOpenShift-OCM-Role-11009103` (linked), CloudFormation stack `factory-test` = VPC `vpc-0392df00b8785402b` with private subnets `subnet-026385fa675cf0cb0` (1a) and `subnet-087b10fc7445ddd16` (1b), public `subnet-06a8762da23b94e6a` (1a) and `subnet-0cfb64f9eda41b121` (1b). The stack probably contains NAT gateways and a VPC endpoint that bill hourly even without a cluster. |
| 2026-11-23 | `rosa create cluster ... --billing-account 105455903431` failed: "billing account not linked to organization ... at the aws marketplace"; without the flag: "A billing account is required for Hosted Control Plane clusters". **Manual step for the user:** enable ROSA in the AWS console (Marketplace subscription) and link the AWS account to the Red Hat organization, then `rosa create cluster -i` should list the billing account. No cluster exists yet. When resuming, rerun the same `rosa create cluster` command: `--cluster-name factory-test --sts --hosted-cp --mode auto --region eu-central-1 --version 4.22.22 --subnet-ids <the four subnets> --oidc-config-id 2u96pmu3hjt9hcrt5183cefqapo0a1i4 --operator-roles-prefix factory-test --compute-machine-type m5.xlarge --replicas 2 --billing-account <id>`. |
| 2026-11-23/24 | **Account 1 (`105455903431`) abandoned:** ROSA could not be linked (AWS account already linked to another Red Hat organization). Its leftovers (account roles, OCM role, OIDC `2u96pmu3hjt9hcrt5183cefqapo0a1i4`, CloudFormation stack `factory-test` with VPC `vpc-0392df00b8785402b`) were **not** deleted. |
| 2026-11-24 | **Account 2 (`850995571480`, alias sandbox3945-gpte):** the org had a stale OCM-role link `juhou-OCM-Role-11009103` for this account (role missing in IAM); with the user's approval it was unlinked (`rosa unlink ocm-role`) and `ManagedOpenShift-OCM-Role-11009103` was created and linked. Created: account roles (prefix `ManagedOpenShift`), OIDC `2u9754j0i82gq99471h6k1n3lp55amnr`, VPC stack `factory-test` (2 AZ), cluster `factory-test` (HCP 4.22.22, 2x m5.xlarge, eu-central-1) which became ready in about 10 minutes. Operators installed (NFD stable, GPU Operator v26.7.3 with `kernelModuleType: auto`, Pipelines 1.24.3) and the CRs `nfd-instance` and `gpu-cluster-policy` created; namespaces `ai` and `agents` created. Pools `gpu-1a` and `gpu-1b` (g7e.12xlarge, taint nvidia.com/gpu) were created. **No GPU node ever started: InsufficientInstanceCapacity in eu-central-1a and eu-central-1b.** Per the user's instruction the cluster and the VPC stack were deleted (the stack failed once on an orphan security group `...-vpce-private-router` left by ROSA; deleting it by hand fixed it). The rosa login expired after about 7 hours; `rosa` needs `! rosa login --use-auth-code` again for long sessions. Left in account 2: account roles, OCM role, operator roles `factory-test-*`, OIDC `2u9754j0i82gq99471h6k1n3lp55amnr` (all free, reusable). |
| 2026-11-24 | Account 2, spot placement scores for g7e.12xlarge (higher is better): **us-east-2c 9** (use2-az3), us-west-2c 3, eu-north-1a 3, others 1 (eu-central-1, ap-south-1 returned no score). GPU quota (L-DB2E81BA) on account 2: 768 in us-east-1, us-west-2, eu-west-2, eu-central-1, ap-northeast-2, ap-south-1; 64 in us-east-2, eu-north-1, ap-northeast-1 (enough for one node, 48 vCPU). |
| 2026-11-24 | **us-west-2 attempt (account 2):** network template allows at most 3 AZ (`AvailabilityZoneCount` <= 3), so subnets exist in a, b, c only (d would need a manually added tagged subnet). With 3 private subnets HCP needs `--replicas` multiple of 3. Cluster `factory-test` (HCP 4.22.22, 3x m5.xlarge) ready in about 9 minutes, operators and CRs installed as before, pools `gpu-a/b/c` created. **InsufficientInstanceCapacity again in a, b and c** (the AWS hint "try the other AZs" is unreliable). The cluster was kept for the user to inspect; API `https://api.factory-test.ggr7.p3.openshiftapps.com:443`, user `cluster-admin`. Reusable in account 2: account roles, OCM role, OIDC `2u9754j0i82gq99471h6k1n3lp55amnr`, operator roles `factory-test-*`. |
| 2026-11-24 | **Capacity test (run-instances in each AZ):** us-west-2 a, b, c, d and us-east-2 a, b: InsufficientInstanceCapacity; **us-east-2c: launched**. Matches the Spot Placement Score (use2-az3 = 9). |
| 2026-11-24 | **Success:** cluster `factory-east` in **us-east-2** (HCP 4.22.22, 3x m5.xlarge, subnets a, b, c; network stack `factory-east` with VPC `vpc-080c53e329a0a4fe4`; operator roles prefix `factory-east`; OIDC `2u9754j0i82gq99471h6k1n3lp55amnr`). Pools `gpu-a`, `gpu-b` (0) and `gpu-c` (1). The GPU node (g7e.12xlarge, us-east-2c) joined within ~5 minutes of the pool creation, with the `nvidia.com/gpu:NoSchedule` taint (no taint sync bug this time). NFD, GPU Operator v26.7.3 and Pipelines 1.24.3 installed; `ClusterPolicy` ready and the node shows `nvidia.com/gpu: 2` (the driver pod needed several minutes); interceptors `github` and `cel` present; default StorageClass `gp3-csi`; namespaces `ai` and `agents` exist. API `https://api.factory-east.b0ur.p3.openshiftapps.com:443`, user `cluster-admin`. GPU quota in us-east-2 is 64 vCPU: enough for exactly one node. |
| 2026-11-24 | Deleted the failed us-west-2 cluster `factory-test` and its VPC stack (the orphan security group `...-vpce-private-router` had to be removed first, again). us-west-2, eu-central-1: no VPCs, NAT gateways or volumes left. Operator roles `factory-test-*` still exist in account 2 (free). |

## Sources

- [G7e announcement (AWS blog)](https://aws.amazon.com/blogs/aws/announcing-amazon-ec2-g7e-instances-accelerated-by-nvidia-rtx-pro-6000-blackwell-server-edition-gpus) and [additional regions, July 2026](https://aws.amazon.com/about-aws/whats-new/2026/07/amazon-g7e-additional-regions/)
- [EC2 instance type quotas](https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-instance-quotas.html)
- [ROSA: managing compute nodes using machine pools](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/cluster_administration/manage-nodes-using-machine-pools)
- [OCPBUGS-31540: machine pool labels and taints not synced on HCP](https://issues.redhat.com/browse/OCPBUGS-31540)
