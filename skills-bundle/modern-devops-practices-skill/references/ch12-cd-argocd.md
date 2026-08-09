# Chapter 12: Continuous Deployment/Delivery with Argo CD

> Part 4: Delivering Applications with GitOps · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to implement pull-based GitOps continuous deployment on Kubernetes with Argo CD: provisioning a GKE cluster declaratively via Terraform + GitHub Actions, installing Argo CD via Terraform, defining `Application`/`ApplicationSet` resources, and storing Kubernetes Secrets safely in Git with Bitnami Sealed Secrets.

## Core concepts
- **CD = the Ops half of DevOps**: CI delivers a tested build to an artifact repo. CD deploys it to test/staging/prod. CD pipelines trigger when a tested build lands in the artifact repo or (GitOps) when the Environment repo changes.
- **Continuous delivery vs. continuous deployment**: Delivery = automated up to prod but prod needs a human trigger (click a button in a maintenance window). Deployment = fully automated to prod the moment a tested build exists. Only a failed test stops it.
- **Toil**: repeatable manual jobs operators do daily. CD removes toil via automation, raising velocity and cutting human error.
- **Application repository vs. Environment repository** (from Ch.2): App repo drives CI (build/test/push image). Environment repo drives CD (declarative manifests of what runs where). This chapter builds the Environment repo.
- **Push vs. pull GitOps**: GitHub Actions + Terraform provisioning the cluster = *push* model. Argo CD polling the Environment repo and reconciling drift = *pull* model.
- **Configuration drift / self-heal**: Argo CD continuously compares Git desired state vs. live cluster state. With `selfHeal: true` it auto-corrects any manual change made outside Git.
- **Application resource**: one app. Defines `source` (Git repo/path/revision) and `destination` (target cluster) plus `syncPolicy`.
- **ApplicationSet resource**: template that *generates* Application resources dynamically (e.g., one per subdirectory under `manifests/*`), avoiding per-app boilerplate.
- **Sealed Secrets**: asymmetric-crypto wrapper for K8s Secrets so they can live in Git. Only the in-cluster Sealed Secrets controller can decrypt. `kubeseal` (client) encrypts.

## Deployment models (choose the right one)
- **Simple deployment**: replace old version with new. Rollback = redeploy old. Disruptive, needs downtime. Manageable by plain CI (Jenkins/GitHub Actions). OK only if no 24/7 users. Otherwise eats SLOs/SLAs.
- **Blue/Green (a.k.a. Red/Black)**: run new (Green) alongside old (Blue), sanity-check Green, switch all traffic, keep Blue for fast rollback, then retire Blue.
- **Canary + A/B testing**: like Blue/Green but shift only a small user subset to the new version (target by location/language/age/beta opt-in), observe logs/behavior, then ramp to 100% and retire old. Complex deployments are hard with traditional CI. Use a CD tool.
- **CD tools named**: Argo CD, Spinnaker, Circle CI, AWS CodeDeploy. Book uses **Argo CD** (GitOps-native, Kubernetes-tailored).

## Tools and versions
- **GKE (Google Kubernetes Engine)**: target cluster, GCP free $300/90-day trial. Cluster master/node version seen: `1.27.3-gke.100`, `e2-medium`, 3 nodes.
- **Terraform 1.5.5**: declarative IaC for the GKE cluster and for installing Argo CD/apps. Remote state in a GCS bucket.
- **GitHub Actions**: runs Terraform on push (push-model GitOps provisioning).
- **Argo CD**: pull-based GitOps CD controller, UI + CLI, supports Helm, Kustomize, Ksonnet, Jsonnet, plain YAML/JSON, plugins. Installed from `argoproj/argo-cd` `manifests/install.yaml`.
- **Sealed Secrets (Bitnami) v0.23.1**: controller (`controller.yaml`) + `kubeseal` client v0.23.1. Controller runs in `kube-system`.
- **Terraform providers/modules**: `gavinbunney/kubectl` (`>= 1.7.0`), `terraform-google-modules/kubernetes-engine/google//modules/auth` (GKE auth), `hashicorp/time` (`time_sleep`).
- **Repo**: clone `https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git` → resources in `ch12/`.

## Workflows (how-to)

### 0. Clone book resources
```bash
$ git clone https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git modern-devops
$ cd modern-devops/ch12
```

### 1. Create the Environment repository (two-branch model)
Branches map to environments: **dev** branch → dev env, **prod** branch → prod env. Terraform workspaces = environments = Git branches.
1. Create a GitHub repo (book uses `mdo-environments`). Add SSH key (see Ch.2), then clone.
2. Add the Terraform `.gitignore` so state/backend/`.tfvars` never get committed:
   ```bash
   $ cp -r ~/modern-devops/ch12/.gitignore .
   $ git add --all && git commit -m 'Added gitignore' && git push
   ```
3. Rename `master` → `prod` in the GitHub branches UI (pencil icon → `prod` → Rename Branch), then re-clone fresh.
4. Branch `dev` off `prod`:
   ```bash
   $ git branch dev && git checkout dev
   ```
5. Copy the Terraform + workflow config in:
   ```bash
   $ cp -r ~/modern-devops/ch12/environments/terraform .
   $ cp -r ~/modern-devops/ch12/environments/.github .
   ```

### 2. Provision GKE with Terraform via GitHub Actions (push GitOps)
Create the Terraform service account, grant it `roles/editor`, download its key, and enable APIs:
```bash
$ PROJECT_ID=<project_id>
$ gcloud iam service-accounts create terraform \
  --description="Service Account for terraform" --display-name="Terraform"
$ gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:terraform@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/editor"
$ gcloud iam service-accounts keys create key-file \
  --iam-account=terraform@$PROJECT_ID.iam.gserviceaccount.com
```
GitHub secrets (repo → Settings → Secrets → Actions): create `GCP_CREDENTIALS` (paste full contents of `key-file`) and `PROJECT_ID` (your GCP project ID).
Create the Terraform remote-state GCS bucket (name must be globally unique, embed the project ID) and enable required APIs:
```bash
$ gsutil mb gs://tf-state-mdo-terraform-${PROJECT_ID}
$ gcloud services enable iam.googleapis.com container.googleapis.com
```
Push to trigger the Actions workflow (it runs `terraform init/workspace/apply`):
```bash
$ git add --all && git commit -m 'Initial commit'
$ git push --set-upstream origin dev
```
Verify the cluster:
```bash
$ gcloud container clusters list
NAME: mdo-cluster-dev   LOCATION: us-central1-a   STATUS: RUNNING   NUM_NODES: 3
```

### 3. Install Argo CD via Terraform (pull GitOps, declarative)
Don't `kubectl apply` Argo CD by hand: install it through the Environment repo so it's in Git too.
```bash
$ cd ~/mdo-environments
$ cp -r ~/modern-devops/ch12/environments-argocd-app/terraform .
$ cp -r ~/modern-devops/ch12/environments-argocd-app/manifests .
$ cp -r ~/modern-devops/ch12/environments-argocd-app/.github .
```
Repo layout after copy:
```
.
├── .github/workflows/create-cluster.yml
├── manifests/argocd/{apps.yaml, install.yaml, namespace.yaml}
└── terraform/{app.tf, argocd.tf, cluster.tf, provider.tf, variables.tf}
```
`argocd.tf` flow: wait 30s after cluster create → authenticate via `gke_auth` module → apply `namespace.yaml` then `install.yaml` via `kubectl_manifest`. `app.tf` applies `apps.yaml` (the ApplicationSet) after Argo CD is installed. Commit and push:
```bash
$ git add --all && git commit -m "Added argocd configuration" && git push
```

### 4. Access the Argo CD Web UI
```bash
$ gcloud container clusters get-credentials mdo-cluster-dev \
  --zone us-central1-a --project $PROJECT_ID
$ kubectl get svc argocd-server -n argocd      # note the LoadBalancer EXTERNAL-IP
```
Visit `https://<external-ip>/`. Default user is `admin`. Rotate the auto-generated password (it comes from a public manifest, so regenerate it):
```bash
$ kubectl patch secret argocd-secret -n argocd \
  -p '{"data": {"admin.password": null, "admin.passwordMtime": null}}'
$ kubectl scale deployment argocd-server --replicas 0 -n argocd
$ kubectl scale deployment argocd-server --replicas 1 -n argocd
# wait ~2 min, then read the new password:
$ kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### 5. Install Sealed Secrets (controller + kubeseal)
Add the controller manifest under `manifests/sealed-secrets/` so Argo CD's ApplicationSet auto-creates a `sealed-secrets` app:
```bash
$ cd ~/mdo-environments/manifests & mkdir sealed-secrets
$ cd sealed-secrets
$ wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.23.1/controller.yaml
# commit + push; after ~5 min Argo CD deploys it
$ kubectl get deployment -n kube-system sealed-secrets-controller   # READY 1/1
```
Install the `kubeseal` client:
```bash
$ KUBESEAL_VERSION='0.23.1'
$ wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION:?}/kubeseal-${KUBESEAL_VERSION:?}-linux-amd64.tar.gz"
$ tar -xvzf kubeseal-${KUBESEAL_VERSION:?}-linux-amd64.tar.gz kubeseal
$ sudo install -m 755 kubeseal /usr/local/bin/kubeseal
$ rm -rf ./kubeseal*
$ kubeseal --version    # kubeseal version: 0.23.1
```

### 6. Create a Sealed Secret (never commit plaintext Secrets)
Pipe a dry-run Secret straight into `kubeseal` (the plaintext Secret is never written to disk):
```bash
$ kubectl create secret generic mongodb-creds \
  --dry-run=client -o yaml --namespace=blog-app \
  --from-literal=MONGO_INITDB_ROOT_USERNAME=root \
  --from-literal=MONGO_INITDB_ROOT_PASSWORD=<your_pwd> \
  | kubeseal -o yaml > mongodb-creds-sealed.yaml
$ mkdir -p ~/mdo-environments/manifests/blog-app/
$ mv mongodb-creds-sealed.yaml ~/mdo-environments/manifests/blog-app/
```
The resulting `SealedSecret` holds `spec.encryptedData` (encrypted, not Base64), safe to commit.

### 7. Deploy the Blog App
```bash
$ cp ~/modern-devops/ch12/blog-app/blog-app.yaml ~/mdo-environments/manifests/blog-app/
# edit image tags (git-sha) to your built images, then commit + push
```
ApplicationSet auto-creates the `blog-app` Argo CD app within ~5 min. Verify:
```bash
$ kubectl get svc -n blog-app     # frontend=LoadBalancer (note EXTERNAL-IP); mongodb=ClusterIP None (headless)
$ kubectl get pod -n blog-app     # mongodb-0 is StatefulSet (ordinal index); others have random UUIDs
$ kubectl get secret -n blog-app  # mongodb-creds (Opaque) proves SealedSecret unsealed correctly
```
Open `http://<frontend-svc-external-ip>` to use the app.

### 8. Promote dev → prod
Raise a pull request from `dev` → `prod`. Merging applies the same manifests to the production environment. PR-based gating provides the human approval step for continuous *delivery*. Environments stay independent while sharing one repo across branches.

## Reference snippets

### `cluster.tf`: GKE cluster + service account (per-branch naming)
```hcl
resource "google_service_account" "main" {
  account_id   = "gke-${var.cluster_name}-${var.branch}-sa"
  display_name = "GKE Cluster ${var.cluster_name}-${var.branch} Service Account"
}
resource "google_container_cluster" "main" {
  name               = "${var.cluster_name}-${var.branch}"
  location           = var.location
  initial_node_count = 3
  node_config {
    service_account = google_service_account.main.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  timeouts { create = "30m"  update = "40m" }
}
```

### `provider.tf`: GCS remote backend (bucket supplied at runtime) + kubectl provider
```hcl
provider "google" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-c"
}
provider "kubectl" {
  host                   = module.gke_auth.host
  cluster_ca_certificate = module.gke_auth.cluster_ca_certificate
  token                  = module.gke_auth.token
  load_config_file       = false
}
terraform {
  backend "gcs" { prefix = "mdo-terraform" }   # bucket passed via -backend-config at init
  required_providers {
    kubectl = { source = "gavinbunney/kubectl"  version = ">= 1.7.0" }
  }
}
```

### `argocd.tf`: wait, auth, apply install manifests
```hcl
resource "time_sleep" "wait_30_seconds" {
  depends_on      = [google_container_cluster.main]
  create_duration = "30s"
}
module "gke_auth" {
  depends_on           = [time_sleep.wait_30_seconds]
  source               = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  project_id           = var.project_id
  cluster_name         = google_container_cluster.main.name
  location             = var.location
  use_private_endpoint = false
}
data "kubectl_file_documents" "namespace" { content = file("../manifests/argocd/namespace.yaml") }
data "kubectl_file_documents" "argocd"    { content = file("../manifests/argocd/install.yaml") }
resource "kubectl_manifest" "namespace" {
  for_each           = data.kubectl_file_documents.namespace.manifests
  yaml_body          = each.value
  override_namespace = "argocd"
}
resource "kubectl_manifest" "argocd" {
  depends_on         = [kubectl_manifest.namespace]
  for_each           = data.kubectl_file_documents.argocd.manifests
  yaml_body          = each.value
  override_namespace = "argocd"
}
```

### `.github/workflows/create-cluster.yml`: Terraform on push
```yaml
name: Create Kubernetes Cluster
on: push
jobs:
  deploy-terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./terraform
    steps:
    - uses: actions/checkout@v2
    - name: Install Terraform
      run: wget -O terraform.zip https://releases.hashicorp.com/terraform/1.5.5/terraform_1.5.5_linux_amd64.zip && unzip terraform.zip && chmod +x terraform && sudo mv terraform /usr/local/bin
    - name: Apply Terraform
      run: terraform init -backend-config="bucket=tf-state-mdo-terraform-${{ secrets.PROJECT_ID }}" && terraform workspace select ${GITHUB_REF##*/} || terraform workspace new ${GITHUB_REF##*/} && terraform apply -auto-approve -var="project_id=${{ secrets.PROJECT_ID }}" -var="branch=${GITHUB_REF##*/}"
      env:
        GOOGLE_CREDENTIALS: ${{ secrets.GCP_CREDENTIALS }}
```

### Argo CD `Application` (single app)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: blog-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your_github_repo>/mdo-environments.git
    targetRevision: HEAD
    path: manifests/nginx
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      selfHeal: true
```

### Argo CD `ApplicationSet` (git directory generator, one app per subdir)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: argo-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/<your_github_repo>/mdo-environments.git
      revision: HEAD
      directories:
      - path: manifests/*
      - path: manifests/argocd        # exclude Argo CD's own config
        exclude: true
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/<your_github_repo>/mdo-environments.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
      syncPolicy:
        automated:
          selfHeal: true
```

### Generated `SealedSecret`
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: mongodb-creds
  namespace: blog-app
spec:
  encryptedData:
    MONGO_INITDB_ROOT_PASSWORD: AgB+tyskf72M/…
    MONGO_INITDB_ROOT_USERNAME: AgA95xKJg8veOy8v/…
  template:
    metadata:
      name: mongodb-creds
      namespace: blog-app
```

### Blog App K8s resource mapping
- **MongoDB**: auth-enabled, root creds from a Secret (env vars), `PersistentVolumeClaim` → dynamic `PersistentVolume`, managed by a `StatefulSet` (pod `mongodb-0`), exposed by a **headless Service** (`ClusterIP: None`).
- **posts / reviews / ratings / users**: `Deployment` each, read same Mongo creds Secret, exposed by individual **ClusterIP** Services on port 5000.
- **frontend**: `Deployment`, no Secret access, exposed via **LoadBalancer** Service on port 80.

## Decision guidance and best practices
- **Don't reuse CI tools for CD beyond simple cases.** CI tools (Jenkins/GitHub Actions) handle simple-replace deploys but get stuck on Blue/Green/canary. Use a purpose-built CD tool (Argo CD).
- **Prefer the pull model for app deployment.** Argo CD polling Git + self-heal gives drift detection and rollback that a one-shot push pipeline doesn't.
- **Install Argo CD via Terraform/Git, not manually**, so the CD tool itself is GitOps-managed and reproducible.
- **Branches = environments.** Preferred Environment-repo branch names: `dev`, `staging`, `prod` (not `feature/develop/master`). Use Terraform workspaces keyed on `${GITHUB_REF##*/}` so one config serves all envs with different vars.
- **Gate prod with pull requests** (dev→prod PR) for continuous delivery, merge = deploy.
- **Never commit plaintext/Base64 Secrets to Git.** Use Sealed Secrets so the whole config (Secrets included) can live in Git.
- **Globally unique GCS bucket name**: embed `<PROJECT_ID>` (e.g., `tf-state-mdo-terraform-<PROJECT_ID>`). Pass `bucket` via `-backend-config` at init, not hardcoded.
- **Rotate the default Argo CD admin password**: it derives from a public manifest.

## Pitfalls and gotchas
- **`time_sleep` is required** before authenticating to a freshly created GKE cluster (book uses 30s) or the API isn't ready.
- **Apply ordering matters**: namespace → Argo CD install → ApplicationSet (`depends_on` chains). Skipping causes "namespace not found" failures.
- **ApplicationSet must exclude `manifests/argocd`** (`exclude: true`) or Argo CD will try to manage its own install config.
- **Sealed Secret namespace is bound at seal time**: a SealedSecret sealed for `blog-app` only unseals in that namespace. Recreate it if the target namespace changes.
- **Sealed Secrets controller lives in `kube-system`**, not `argocd`, look there to verify it's running.
- **Base64 ≠ encryption**: a plain K8s Secret is only Base64-encoded, hence unsafe for Git. That's the whole reason for Sealed Secrets.
- **`gcloud` is not declarative**: don't provision clusters with it under GitOps. Use Terraform.
- Allow propagation time: Argo CD picks up new manifests in "less than five minutes," not instantly. Password regeneration takes ~2 minutes.

## Command / API cheat-sheet
- `terraform init -backend-config="bucket=..."`: init with runtime-supplied GCS state bucket.
- `terraform workspace select <env> || terraform workspace new <env>`: env-per-workspace.
- `terraform apply -auto-approve -var="branch=..."`: non-interactive apply in CI.
- `gcloud iam service-accounts create terraform`: create Terraform SA.
- `gcloud projects add-iam-policy-binding ... --role="roles/editor"`: grant SA permissions.
- `gcloud iam service-accounts keys create key-file --iam-account=...`: download SA JSON key.
- `gsutil mb gs://tf-state-mdo-terraform-${PROJECT_ID}`: make state bucket.
- `gcloud services enable iam.googleapis.com container.googleapis.com`: enable APIs.
- `gcloud container clusters list` / `get-credentials <cluster> --zone ... --project ...`: list / auth to GKE.
- `kubectl get svc argocd-server -n argocd`: find Argo CD UI LoadBalancer IP.
- `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`: read admin password.
- `kubectl patch secret argocd-secret -n argocd -p '{...null...}'` + scale 0→1: rotate admin password.
- `kubectl create secret generic ... --dry-run=client -o yaml | kubeseal -o yaml`: produce a SealedSecret.
- `kubeseal --version`: verify client install.
- `kubectl get deployment -n kube-system sealed-secrets-controller`: verify controller.
- **CRDs**: `Application` (argoproj.io/v1alpha1), `ApplicationSet` (argoproj.io/v1alpha1), `SealedSecret` (bitnami.com/v1alpha1).

## Where this is covered (topic index)
- CD vs CI, delivery vs deployment, toil → "Core concepts".
- Deployment strategies (simple / Blue-Green / Red-Black / canary / A/B testing) → "Deployment models".
- CD tool choices (Argo CD, Spinnaker, Circle CI, AWS CodeDeploy) → "Deployment models".
- Environment repository, dev/prod branches, Terraform workspaces → Workflow 1 & 2, best practices.
- GKE provisioning with Terraform + GitHub Actions (push GitOps) → Workflow 2, `cluster.tf`/`provider.tf`/workflow snippets.
- GCS remote Terraform backend / state bucket → Workflow 2, `provider.tf`.
- Installing Argo CD via Terraform (kubectl provider, gke_auth, time_sleep) → Workflow 3, `argocd.tf`.
- Argo CD Web UI access / admin password rotation → Workflow 4.
- Argo CD Application resource (source/destination/syncPolicy/selfHeal) → "Reference snippets".
- Argo CD ApplicationSet / git directory generator / templates → "Reference snippets", Core concepts.
- Drift detection / self-heal / pull model → Core concepts, pitfalls.
- Sealed Secrets / kubeseal / Bitnami controller / secrets in Git → Workflow 5 & 6, SealedSecret snippet.
- Blog App manifests (StatefulSet, headless Service, LoadBalancer, ClusterIP, PVC) → "Blog App K8s resource mapping", Workflow 7.
- dev→prod promotion / PR gating → Workflow 8.
- Synonyms: "GitOps deployment", "continuous delivery Kubernetes", "Argo CD setup", "encrypt Kubernetes secrets for git", "Terraform GKE GitHub Actions", "Argo CD app of apps / ApplicationSet generator".
