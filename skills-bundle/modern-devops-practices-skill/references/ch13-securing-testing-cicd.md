# Chapter 13: Securing and Testing Your CI/CD Pipeline

> Part 4: Delivering Applications with GitOps · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to embed security and automated testing into a GitOps CI/CD pipeline: container vulnerability scanning, externalized secrets management, integration tests in CD, deploy-time binary authorization (image attestation), and pull-request release gating between Dev and Prod on GKE.

## Core concepts
- **DevSecOps**: shift security left so developers, security, and ops collaborate from the start. Automate security so it does not slow delivery.
- **Secure CI/CD workflow shape**: one CI pipeline (build + vuln scan), plus two CD pipelines: Dev (deploy → integration test → attest images → raise PR) and Prod (deploy → integration test). Workflows are split into parent + reusable child workflows.
- **Container vulnerability scanning**: scan built images for known CVEs and fail the pipeline above a severity threshold, before the image reaches the registry.
- **Secrets management**: never store secrets in Git or bake them into images. Keep them in a dedicated secret store (GCP Secret Manager) and pull them into the cluster at runtime via External Secrets Operator.
- **Binary authorization**: a deploy-time admission-controller mechanism (GKE, based on open-source Kritis) that uses PKI to allow only images signed (attested) by a trusted authority. Images must be referenced by `sha256` digest, not tag.
- **Release gating**: a human-approved pull request from `dev` → `prod` is the promotion gate. Merging triggers the Prod CD workflow.
- **Integration tests vs unit tests**: CI runs per-microservice unit tests in isolation. CD runs a black-box integration test against the whole deployed app.

## Tools and versions
- **GKE / Google Cloud Platform**: managed Kubernetes for the exercises (free $300/90-day trial). Cloud Shell used to run commands.
- **Anchore Grype** (github.com/anchore/grype): CLI container vulnerability scanner, install as a binary, run locally or in CI.
- **GCP Secret Manager**: secret store, backed by HSMs, versioned secrets referenced by version number or `latest`.
- **External Secrets Operator** v0.9.4 (external-secrets.io): Kubernetes operator (Helm chart) bridging the cluster to external stores, installed via Argo CD.
- **Argo CD**: GitOps CD, deploys the Helm chart and the blog-app.
- **Google Cloud KMS**: PKI key ring for binary-authorization attestor signing.
- **Terraform** with the `kubectl` provider and Google `binary-authorization` module (`terraform-google-modules/kubernetes-engine/google//modules/binary-authorization`).
- **GitHub Actions**: CI/CD orchestration with reusable `workflow_call` child workflows.
- **gcloud beta** (`container binauthz`): image attestation CLI.
- Sample app: **Blog App** (MongoDB StatefulSet + posts/reviews/ratings/users Deployments + frontend LoadBalancer). Repos: `mdo-posts` (CI), `mdo-environments` (GitOps env/CD).
- Book repo: github.com/PacktPublishing/Modern-DevOps-Practices-2e (files under `ch13/`).

### One-time GCP setup
```bash
git clone https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git modern-devops
PROJECT_ID=<YOUR_PROJECT_ID>
gcloud services enable iam.googleapis.com \
  container.googleapis.com \
  binaryauthorization.googleapis.com \
  containeranalysis.googleapis.com \
  secretmanager.googleapis.com \
  cloudresourcemanager.googleapis.com \
  cloudkms.googleapis.com
```

## Workflows (how-to)

### 1. Container vulnerability scanning with Grype in CI
Modify the `mdo-posts` CI workflow (`build.yaml`).

1. Install Grype before the Docker Hub login step:
```yaml
- name: Install Grype
  id: install-grype
  run: curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
```
2. Add a scan step after the build-image step. `-f critical` fails the build if any vulnerability is `Critical` or worse:
```yaml
- name: Scan Image for Vulnerabilities
  id: vul-scan
  run: grype -f critical ${{ secrets.DOCKER_USER }}/mdo-posts:$(git rev-parse --short "$GITHUB_SHA")
```
3. Commit/push:
```bash
cp ~/modern-devops/ch13/grype/build.yaml .
git add --all && git commit -m "Added grype" && git push
```
4. If the scan fails on a `Critical`, fix by updating the base image (book swaps `python:3.7-alpine` → `python:alpine3.18`), then push the new Dockerfile:
```bash
cd ~/mdo-posts && cp ~/modern-devops/ch13/grype/Dockerfile .
git add --all && git commit -m "Updated base image" && git push
```
Severity levels reported: `Negligible`, `Low`, `Medium`, `High`, `Critical`, `Unknown`.

### 2. Create a secret in GCP Secret Manager
```bash
echo -ne \
'{"MONGO_INITDB_ROOT_USERNAME": "root", "MONGO_INITDB_ROOT_PASSWORD": "itsasecret"}' \
| gcloud secrets create external-secrets --locations=us-central1 \
  --replication-policy=user-managed --data-file=-
```
This is a development-time action, kept out of CI/CD. Each write creates a new version. Replicating to multiple regions is recommended for resilience (single location chosen here only to save cost).

### 3. Install External Secrets Operator via Argo CD + Terraform
1. Argo CD Application manifest `manifests/argocd/external-secrets.yaml` (see Reference snippets).
2. Apply it with the `kubectl` Terraform provider in `app.tf` (see Reference snippets).
3. Push to `mdo-environments` (dev branch). GitHub Actions creates the cluster and deploys Argo CD + the operator:
```bash
cp ~/modern-devops/ch13/install-external-secrets/app.tf terraform/app.tf
cp ~/modern-devops/ch13/install-external-secrets/external-secrets.yaml manifests/argocd/
git add --all && git commit -m "Install external secrets operator" && git push
```
4. Access Argo CD:
```bash
gcloud container clusters get-credentials mdo-cluster-dev --zone us-central1-a --project $PROJECT_ID
kubectl get svc argocd-server -n argocd          # grab EXTERNAL-IP
# reset admin password:
kubectl patch secret argocd-secret -n argocd -p '{"data": {"admin.password": null, "admin.passwordMtime": null}}'
kubectl scale deployment argocd-server --replicas 0 -n argocd
kubectl scale deployment argocd-server --replicas 1 -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```
5. Remove the old SealedSecrets (we switch to Secret Manager):
```bash
rm -rf manifests/sealed-secrets
git add --all && git commit -m "Removed sealed secrets" && git push
```

### 4. Generate the mongodb-creds Kubernetes Secret from Secret Manager
Three resources: a `Secret` (SA creds), a `ClusterSecretStore` (connection to GCP SM), an `ExternalSecret` (mapping to the target K8s Secret).

1. Create a least-privilege GCP service account scoped to just the `external-secrets` secret:
```bash
gcloud iam service-accounts create external-secrets
gcloud secrets add-iam-policy-binding external-secrets \
  --member "serviceAccount:external-secrets@$PROJECT_ID.iam.gserviceaccount.com" \
  --role "roles/secretmanager.secretAccessor"
gcloud iam service-accounts keys create key.json \
  --iam-account=external-secrets@$PROJECT_ID.iam.gserviceaccount.com
```
2. Put `key.json` contents into a GitHub Actions secret `GCP_SM_CREDENTIALS` (injected at runtime into the `SECRET_ACCESS_CREDS_PH` placeholder in `gcpsm-secret.yaml`).
3. Apply manifests + Terraform and push:
```bash
cd ~/mdo-environments
cp ~/modern-devops/ch13/configure-external-secrets/app.tf terraform/app.tf
cp ~/modern-devops/ch13/configure-external-secrets/gcpsm-secret.yaml manifests/argocd/
cp ~/modern-devops/ch13/configure-external-secrets/mongodb-creds-external.yaml manifests/blog-app/
cp -r ~/modern-devops/ch13/configure-external-secrets/.github .
git add --all && git commit -m "Configure External Secrets" && git push
```
4. Verify:
```bash
kubectl get secret gcpsm-secret
kubectl get clustersecretstore gcp-backend          # STATUS Valid, READY True
kubectl get externalsecret -n blog-app mongodb-creds # STATUS SecretSynced, READY True
kubectl get secret -n blog-app mongodb-creds
kubectl get svc -n blog-app frontend                 # browse http://<EXTERNAL-IP>
```

### 5. Add integration tests to the CD pipeline
Python black-box integration test suite lives under `./tests/integration-test.py`. Add a `run-tests` job (calls reusable `run-tests.yml`) to both Dev and Prod CD workflows. Push:
```bash
cp -r ~/modern-devops/ch13/integration-tests/.github .
cp -r ~/modern-devops/ch13/integration-tests/tests .
git add --all && git commit -m "Added tests" && git push
```
The `run-tests.yml` workflow authenticates to gcloud, gets GKE credentials for `mdo-cluster-<branch>`, resolves the frontend LoadBalancer IP, rewrites `localhost` → external IP in `integration-test.py`, then runs `python3 integration-test.py`.

### 6. Set up binary authorization (image attestation)
1. Create GitHub Actions secrets:
```
ATTESTOR_NAME=quality-assurance-attestor
KMS_KEY_LOCATION=us-central1
KMS_KEYRING_NAME=qa-attestor-keyring
KMS_KEY_NAME=quality-assurance-attestor-key
KMS_KEY_VERSION=1
```
2. Add `binaryauth.tf` (KMS key ring + attestor module + policy), enable binary auth on the Prod cluster in `cluster.tf`. All attestor/policy resources use `count = var.branch == "dev" ? 1 : 0`. The cluster `binary_authorization` block is created only for `prod`. Rationale: deploy unattested to Dev, test, attest on success, then enforce only in Prod.
3. Convert all image tags in `manifests/blog-app` to `sha256` digests (binary auth requires digests, not tags):
```bash
grep -ir "image:" ./manifests/blog-app | awk {'print $3'} | sort -t: -u -k1,1 > ./images
for image in $(cat ./images); do
  no_of_slash=$(echo $image | tr -cd '/' | wc -c)
  prefix=""
  if [ $no_of_slash -eq 1 ]; then prefix="docker.io/"; fi
  if [ $no_of_slash -eq 0 ]; then prefix="docker.io/library/"; fi
  image_to_attest=$image
  if [[ $image =~ "@" ]]; then
    image_to_attest="${prefix}${image}"
  else
    DIGEST=$(docker pull $image | grep Digest | awk {'print $2'})
    image_name=$(echo $image | awk -F ':' {'print $1'})
    image_to_attest="${prefix}${image_name}@${DIGEST}"
  fi
  escaped_image=$(printf '%s\n' "${image}" | sed -e 's/[]\/$*.^[]/\\&/g')
  escaped_image_to_attest=$(printf '%s\n' "${image_to_attest}" | sed -e 's/[]\/$*.^[]/\\&/g')
  grep -rl $image ./manifests | xargs sed -i "s/${escaped_image}/${escaped_image_to_attest}/g"
done
cat manifests/blog-app/blog-app.yaml | grep "image:"   # verify @sha256 form
```
4. Add the `binary-auth` job (calls `attest-images.yml`) to the Dev workflow. Push:
```bash
cp ~/modern-devops/ch13/binaryauth/binaryauth.tf terraform/
cp ~/modern-devops/ch13/binaryauth/cluster.tf terraform/
cp ~/modern-devops/ch13/binaryauth/variables.tf terraform/
cp -r ~/modern-devops/ch13/binaryauth/.github .
git add --all && git commit -m "Enabled Binary Auth" && git push
```
5. Verify attestations:
```bash
gcloud beta container binauthz attestations list \
  --attestor-project="$PROJECT_ID" \
  --attestor="quality-assurance-attestor" | grep resourceUri
```

### 7. Release gating with a pull request, then deploy to Prod
1. Create a fine-grained GitHub PAT (github.com/settings/personal-access-tokens/new) with Repository access to `mdo-environments` and read-write Pull request permission. Store it as the `GH_TOKEN` Actions secret.
2. Add the `raise-pull-request` job (calls `raise-pr.yml`, which uses `repo-sync/pull-request@v2` to PR into `prod`). Push:
```bash
cd ~/mdo-environments/.github/workflows
cp ~/modern-devops/ch13/raise-pr/.github/workflows/dev-cd-workflow.yml .
cp ~/modern-devops/ch13/raise-pr/.github/workflows/raise-pr.yml .
git add --all && git commit -m "Added PR Gating" && git push
```
3. Manually review and merge the PR (the release gate). Merge into `prod` triggers the Prod CD workflow (create env, deploy, integration test, with binary auth enforced).
4. Confirm binary auth blocks unattested images on Prod:
```bash
gcloud container clusters get-credentials mdo-cluster-prod --zone us-central1-a --project ${PROJECT_ID}
kubectl run nginx --image=nginx            # denied: not a sha256 digest
DIGEST=$(docker pull nginx | grep Digest | awk {'print $2'})
kubectl run nginx --image=nginx@$DIGEST    # denied: no valid attestation
```

## Reference snippets

### Dev CD parent workflow (reusable child workflows)
```yaml
name: Dev Continuous Delivery Workflow
on:
  push:
    branches: [ dev ]
jobs:
  create-environment-and-deploy-app:
    name: Create Environment and Deploy App
    uses: ./.github/workflows/create-cluster.yml
    secrets: inherit
  run-tests:
    name: Run Integration Tests
    needs: [create-environment-and-deploy-app]
    uses: ./.github/workflows/run-tests.yml
    secrets: inherit
  binary-auth:
    name: Attest Images
    needs: [run-tests]
    uses: ./.github/workflows/attest-images.yml
    secrets: inherit
  raise-pull-request:
    name: Raise Pull Request
    needs: [binary-auth]
    uses: ./.github/workflows/raise-pr.yml
    secrets: inherit
```
Prod CD workflow is identical but triggers on `branches: [ prod ]` and omits `binary-auth` and `raise-pull-request`.

### run-tests.yml (integration test child workflow)
```yaml
name: Run Integration Tests
on: [workflow_call]
jobs:
  test-application:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./tests
    steps:
    - uses: actions/checkout@v2
    - name: Extract branch name
      run: echo "branch=${GITHUB_HEAD_REF:-${GITHUB_REF#refs/heads/}}" >> $GITHUB_OUTPUT
      id: extract_branch
    - id: gcloud-auth
      name: Authenticate with gcloud
      uses: 'google-github-actions/auth@v1'
      with:
        credentials_json: '${{ secrets.GCP_CREDENTIALS }}'
    - name: Set up Cloud SDK
      uses: 'google-github-actions/setup-gcloud@v1'
    - name: Get kubectl credentials
      uses: 'google-github-actions/get-gke-credentials@v1'
      with:
        cluster_name: mdo-cluster-${{ steps.extract_branch.outputs.branch }}
        location: ${{ secrets.CLUSTER_LOCATION }}
    - name: Compute Application URL
      run: external_ip=$(kubectl get svc -n blog-app frontend --output jsonpath='{.status.loadBalancer.ingress[0].ip}') && echo ${external_ip} && sed -i "s/localhost/${external_ip}/g" integration-test.py
    - id: run-integration-test
      name: Run Integration Test
      run: python3 integration-test.py
```

### Argo CD Application for External Secrets Operator (Helm)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets
  namespace: argocd
spec:
  project: default
  source:
    chart: external-secrets/external-secrets
    repoURL: https://charts.external-secrets.io
    targetRevision: 0.9.4
    helm:
      releaseName: external-secrets
  destination:
    server: "https://kubernetes.default.svc"
    namespace: external-secrets
```

### Terraform: apply Argo CD Application manifest
```hcl
data "kubectl_file_documents" "external-secrets" {
  content = file("../manifests/argocd/external-secrets.yaml")
}
resource "kubectl_manifest" "external-secrets" {
  depends_on         = [kubectl_manifest.argocd]
  for_each           = data.kubectl_file_documents.external-secrets.manifests
  yaml_body          = each.value
  override_namespace = "argocd"
}
```

### External Secrets: Secret + ClusterSecretStore + ExternalSecret
```yaml
apiVersion: v1
data:
  secret-access-credentials: SECRET_ACCESS_CREDS_PH   # injected by GitHub Actions at runtime
kind: Secret
metadata:
  name: gcpsm-secret
type: Opaque
---
apiVersion: external-secrets.io/v1alpha1
kind: ClusterSecretStore
metadata:
  name: gcp-backend
spec:
  provider:
    gcpsm:
      auth:
        secretRef:
          secretAccessKeySecretRef:
            name: gcpsm-secret
            key: secret-access-credentials
      projectID: PROJECT_ID_PH
---
apiVersion: external-secrets.io/v1alpha1
kind: ExternalSecret
metadata:
  name: mongodb-creds
  namespace: blog-app
spec:
  secretStoreRef:
    kind: SecretStore
    name: gcp-backend
  target:
    name: mongodb-creds
  data:
  - secretKey: MONGO_INITDB_ROOT_USERNAME
    remoteRef:
      key: external-secrets
      property: MONGO_INITDB_ROOT_USERNAME
  - secretKey: MONGO_INITDB_ROOT_PASSWORD
    remoteRef:
      key: external-secrets
      property: MONGO_INITDB_ROOT_PASSWORD
```

### Terraform: binary authorization (KMS ring, attestor, policy)
```hcl
resource "google_kms_key_ring" "qa-attestor-keyring" {
  count    = var.branch == "dev" ? 1 : 0
  name     = "qa-attestor-keyring"
  location = var.region
  lifecycle { prevent_destroy = false }
}

module "qa-attestor" {
  count         = var.branch == "dev" ? 1 : 0
  source        = "terraform-google-modules/kubernetes-engine/google//modules/binary-authorization"
  attestor-name = "quality-assurance"
  project_id    = var.project_id
  keyring-id    = google_kms_key_ring.qa-attestor-keyring[0].id
}

resource "google_binary_authorization_policy" "policy" {
  count = var.branch == "dev" ? 1 : 0
  admission_whitelist_patterns { name_pattern = "gcr.io/google_containers/*" }
  admission_whitelist_patterns { name_pattern = "gcr.io/google-containers/*" }
  admission_whitelist_patterns { name_pattern = "k8s.gcr.io/**" }
  admission_whitelist_patterns { name_pattern = "gke.gcr.io/**" }
  admission_whitelist_patterns { name_pattern = "gcr.io/stackdriver-agents/*" }
  admission_whitelist_patterns { name_pattern = "quay.io/argoproj/*" }
  admission_whitelist_patterns { name_pattern = "ghcr.io/dexidp/*" }
  admission_whitelist_patterns { name_pattern = "docker.io/redis[@:]*" }
  admission_whitelist_patterns { name_pattern = "ghcr.io/external-secrets/*" }
  global_policy_evaluation_mode = "ENABLE"
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = [module.qa-attestor[0].attestor]
  }
}
```

### Terraform: enable binary auth on the Prod cluster (cluster.tf)
```hcl
resource "google_container_cluster" "main" {
  # ...
  dynamic "binary_authorization" {
    for_each = var.branch == "prod" ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }
  # ...
}
```

### attest-images.yml core step (sign-and-create)
```yaml
- name: Install gcloud beta
  run: gcloud components install beta
- name: Attest Images
  run: |
    for image in $(cat ./images); do
      # ... compute docker.io prefix by slash count ...
      if [[ $image =~ "@" ]]; then image_to_attest="${prefix}${image}"
      else echo "All images should be in the SHA256 digest format"; exit 1; fi
      attestation_present=$(gcloud beta container binauthz attestations list \
        --attestor-project="${{ secrets.PROJECT_ID }}" --attestor="${{ secrets.ATTESTOR_NAME }}" \
        --artifact-url="${image_to_attest}")
      if [ -z "${attestation_present// }" ]; then
        gcloud beta container binauthz attestations sign-and-create \
          --artifact-url="${image_to_attest}" --attestor="${{ secrets.ATTESTOR_NAME }}" \
          --attestor-project="${{ secrets.PROJECT_ID }}" --keyversion-project="${{ secrets.PROJECT_ID }}" \
          --keyversion-location="${{ secrets.KMS_KEY_LOCATION }}" --keyversion-keyring="${{ secrets.KMS_KEYRING_NAME }}" \
          --keyversion-key="${{ secrets.KMS_KEY_NAME }}" --keyversion="${{ secrets.KMS_KEY_VERSION }}"
      fi
    done
```

### raise-pr.yml core step
```yaml
- uses: actions/checkout@v2
- name: Raise a Pull Request
  id: pull-request
  uses: repo-sync/pull-request@v2
  with:
    destination_branch: prod
    github_token: ${{ secrets.GH_TOKEN }}
```

### Digest image reference format
```
<repo_url>/<image_name>@sha256:<sha256-digest>
```

## Decision guidance and best practices
- **Adopt DevSecOps culture**: cross-skill dev/sec/ops. Security collaborates, not just reviews.
- **Principle of Least Privilege (PoLP)**: grant only required access (e.g., scope the SA to a single secret with `secretmanager.secretAccessor`). Make granting access easy to avoid "just-in-case" over-provisioning.
- **Shift left**: build security in from design/early dev, not as a final gate.
- **Automate security in CI/CD**: vuln scanning, config/infra scanning, policy-as-code, binary authorization, keep humans out of the hot path.
- **Keep base images current**: newer base images carry fewer/older-fixed vulnerabilities (Alpine is the most secure / fewest vulnerabilities of Alpine/Slim/Buster/Default).
- **Secrets location ranking**: secret management system > everything. Never a Git repo (public or private) or a Docker image.
- **Replicate secrets** across regions for resilience (book used single region only to save cost).
- **Use digests, not tags, for attested images**: a digest is content-addressed and cannot be re-pointed to a different image.
- **Enforce binary auth in Prod only**: deploy unattested to Dev, test, attest, then enforce in Prod via PR gating.
- **Testing**: automate unit + integration + functional + security + performance, isolate/reproduce test environments (containers/virtualization), manage and anonymize test data, do end-to-end, load, and scalability testing, add chaos engineering, monitor/observe during tests, test in production safely via feature flags and canary releases with continuous monitoring and easy rollback, and document procedures and share knowledge.

## Pitfalls and gotchas
- Baking secrets into a container image or committing them to Git is a common, severe leak. Never do it.
- Do **not** download/log a secret to the CD pipeline filesystem (External Secrets keeps it out of logs and Git).
- SealedSecrets are tied to the controller that encrypted them: lose/recreate the controller and the secret is unrecoverable. Access requires `kubectl` cluster login (poor for non-admins). This is why the chapter moves to Secret Manager + External Secrets Operator.
- Binary authorization rejects any image referenced by tag: `Expected digest with sha256 scheme, but got tag or malformed digest`. Convert all manifests to `@sha256:` form first.
- An unattested image (even by digest) is denied: `No attestations found that were valid and signed by a key trusted by the attestor`.
- Whitelist system/infra images (Google system, `quay.io/argoproj/*`, `ghcr.io/dexidp/*`, `ghcr.io/external-secrets/*`, `docker.io/redis`) in the policy, and set `global_policy_evaluation_mode = "ENABLE"`, or platform pods fail admission.
- A fresh cluster's SealedSecrets controller cannot decrypt SealedSecrets created by a previous controller. The app shows Degraded until the secret is regenerated.
- `grype -f critical` fails the whole CI build. Align the threshold with your risk tolerance.

## Command / API cheat-sheet
- `grype <image>`: scan image for vulnerabilities.
- `grype -f critical <image>`: fail if any vuln >= Critical.
- `gcloud secrets create <name> --replication-policy=user-managed --locations=<region> --data-file=-`: create a Secret Manager secret.
- `gcloud secrets add-iam-policy-binding <secret> --member ... --role roles/secretmanager.secretAccessor`: grant least-privilege read on one secret.
- `gcloud iam service-accounts keys create key.json --iam-account=...`: create SA key.
- `kubectl get clustersecretstore <name>` / `kubectl get externalsecret -n <ns> <name>`: check External Secrets sync (READY/STATUS).
- `gcloud beta container binauthz attestations list --attestor-project=... --attestor=...`: list attestations.
- `gcloud beta container binauthz attestations sign-and-create --artifact-url=...@sha256:... --attestor=... --keyversion-*=...`: attest an image.
- `kubectl run nginx --image=nginx@$DIGEST`: test that binary auth blocks unattested digests.
- `repo-sync/pull-request@v2`: GitHub Action to raise a gating PR into `prod`.
- `google-github-actions/{auth,setup-gcloud,get-gke-credentials}@v1`: GCP auth + GKE creds in Actions.
- Argo CD `kind: Application` with `source.chart` + `repoURL` + `targetRevision`: install a Helm chart via GitOps.

## Where this is covered (topic index)
- Secure CI/CD workflow shape / parent-child reusable workflows -> Core concepts, Dev/Prod CD snippets.
- Vulnerability scanning / Grype / Anchore / CVE / image scan / fail threshold -> Workflow 1.
- Base image upgrade to fix CVEs / Alpine -> Workflow 1, Best practices.
- Secrets management / GCP Secret Manager / do not store secrets in Git -> Workflows 2, Best practices, Pitfalls.
- External Secrets Operator / ClusterSecretStore / ExternalSecret / gcpsm -> Workflows 3-4, Reference snippets.
- SealedSecrets removal / why move off SealedSecrets -> Workflow 3, Pitfalls.
- Helm chart install via Argo CD -> Workflow 3, Argo CD Application snippet.
- Argo CD admin password reset / access UI -> Workflow 3.
- Integration testing in CD / black-box / run-tests.yml -> Workflow 5, run-tests.yml snippet.
- Binary authorization / Kritis / attestation / PKuI / KMS / admission controller -> Workflow 6, Terraform binary-auth snippets.
- sha256 digest vs tag requirement / convert manifests -> Workflow 6, Pitfalls, digest format snippet.
- Attestor / sign-and-create / verify attestations -> Workflow 6, attest-images.yml snippet, cheat-sheet.
- Enforce binary auth on Prod cluster only -> Workflow 6, cluster.tf snippet.
- Release gating / pull request / dev->prod promotion / GH_TOKEN PAT -> Workflow 7, raise-pr.yml snippet.
- Deploy to Prod / verify unattested images blocked -> Workflow 7.
- DevSecOps culture / shift left / PoLP / automate security -> Best practices.
- Chaos engineering / canary releases / feature flags / test in production / load & scalability testing -> Best practices.
