# Chapter 15: Implementing Traffic Management, Security, and Observability with Istio

> Part 5: Operating Applications in Production · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to add an Istio service mesh to a Kubernetes app via GitOps (Argo CD + Helm): inject sidecars, expose apps through an Istio ingress gateway with TLS, enforce mTLS and authorization policies between microservices, do canary rollouts / traffic mirroring, or wire up observability (Kiali, Grafana, Prometheus). Uses GKE + Argo CD + Terraform + the Blog App from earlier chapters.

## Core concepts
- **Service mesh**: centralized infrastructure layer that manages, secures, and observes service-to-service communication via injected sidecar proxies. Solves what Kubernetes alone does not: pod-to-pod TLS, L7 (HTTP-header) routing, intelligent percentage-based traffic splitting, log consolidation, and request tracing.
- **Why not plain Kubernetes**: default pod traffic is plaintext. NetworkPolicy is L3 not L7. Canary by replica-scaling is coarse (10% needs 9+1 pods). No built-in cross-service tracing.
- **Data plane**: the injected Envoy sidecar proxies (L7) that route business traffic and emit telemetry, plus ingress/egress gateways.
- **Control plane (`istiod`)**: single component instructing the data plane. Sub-roles: **Pilot** (service discovery, translates Istio CRDs to Envoy config, traffic mgmt, resiliency), **Citadel** (identity/access mgmt, mTLS certificate management), **Galley** (config validation, processing, distribution).
- **Sidecar injection**: Envoy is added per-pod so the proxy owns the pod's network namespace/IP tables and intercepts all traffic. Each meshed pod shows `2/2` containers.
- **mTLS modes**: default is **PERMISSIVE/compatibility** (meshed pods talk TLS, non-meshed can still use plaintext). **STRICT** rejects plaintext.
- **Gateway vs VirtualService vs DestinationRule**: Gateway = mesh entry point/load balancer (ports, hosts, TLS). VirtualService = routing rules (path match, traffic split, retries, timeouts, mirroring). DestinationRule = defines named **subsets** (e.g. v1/v2 by pod label) that VirtualServices target.
- **Canary rollout (Blue/Green)**: shift traffic incrementally from old (Blue) to new (Green) version via VirtualService `weight`.
- **Traffic mirroring (shadowing)**: old version serves users. An async copy of live traffic is sent to the new version for testing without affecting end users.
- **AuthorizationPolicy**: has an implicit deny-all once a selector matches. `ALLOW` rules add exceptions. Identity is by workload **service account** (principal `cluster.local/ns/<ns>/sa/<sa>`).

## Tools and versions
- **Istio 1.19.1**: installed via Helm charts (`base`, `istiod`, `gateway`) from `https://istio-release.storage.googleapis.com/charts`.
- **Argo CD**: GitOps deploy of the Helm charts (instead of `istioctl`).
- **Terraform** (`kubectl_manifest` provider): push-based GitOps to create Argo CD Applications.
- **GKE** cluster `mdo-cluster-dev` (zone `us-central1-a`), GCP free trial.
- **External Secrets** + **Google Secret Manager**: store TLS key/cert out of Git.
- **Kiali, Grafana, Prometheus**: observability add-ons installed via Argo CD.
- Repo files: `github.com/PacktPublishing/Modern-DevOps-Practices-2e`, dir `ch15/` (subdirs `baseline/`, `install-istio/`, `istio-ingressgateway/`, `security/`, `traffic-management/`, `observability/`). Environment repo: `mdo-environments` (branches `prod`/`dev`).

## Workflows (how-to)

### 1. Install Istio via Argo CD + Helm (GitOps)
Create three Argo CD `Application` resources (in `istio.yaml`) for `istio-base`, `istiod` (both to `istio-system`), and `istio-ingress` (the `gateway` chart, to `istio-ingress`). Base example:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: istio-base
  namespace: argo
spec:
  project: default
  source:
    chart: base
    repoURL: https://istio-release.storage.googleapis.com/charts
    targetRevision: 1.19.1
    helm:
      releaseName: istio-base
  destination:
    server: "https://kubernetes.default.svc"
    namespace: istio-system
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    automated:
      selfHeal: true
```
`istiod` uses `chart: istiod` → `istio-system`. Ingress uses `chart: gateway`, `releaseName: istio-ingress` → namespace `istio-ingress`.

Register via Terraform in `app.tf` (so the workflow auto-creates them):
```hcl
data "kubectl_file_documents" "istio" {
    content = file("../manifests/argocd/istio.yaml")
}
resource "kubectl_manifest" "istio" {
  depends_on = [ kubectl_manifest.gcpsm-secrets ]
  for_each  = data.kubectl_file_documents.istio.manifests
  yaml_body = each.value
  override_namespace = "argocd"
}
```
Commit & push. GitHub Actions applies Terraform, Argo CD reconciles.
```bash
cp -a ~/modern-devops/ch15/install-istio/app.tf   ~/mdo-environments/terraform/app.tf
cp -a ~/modern-devops/ch15/install-istio/istio.yaml ~/mdo-environments/manifests/argocd/istio.yaml
git add --all && git commit -m "Install istio" && git push
```
Get cluster creds & Argo CD UI / password:
```bash
gcloud container clusters get-credentials mdo-cluster-dev --zone us-central1-a --project $PROJECT_ID
kubectl get svc argocd-server -n argocd          # external IP for UI
# reset admin password
kubectl patch secret argocd-secret -n argocd -p '{"data": {"admin.password": null, "admin.passwordMtime": null}}'
kubectl scale deployment argocd-server --replicas 0 -n argocd
kubectl scale deployment argocd-server --replicas 1 -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### 2. Enable automatic sidecar injection
Label the namespace, then restart workloads so sidecars are injected.
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: blog-app
  labels:
    istio-injection: enabled
```
```bash
kubectl -n blog-app rollout restart deploy frontend posts users reviews ratings
kubectl -n blog-app rollout restart statefulset mongodb
kubectl get pod -n blog-app    # pods now show READY 2/2 (app + envoy)
```

### 3. Expose the app through the Istio ingress gateway (HTTP)
Find the ingress LB, create a `Gateway` + `VirtualService`, switch the app Service from `LoadBalancer` to `ClusterIP`.
```bash
kubectl get svc istio-ingress -n istio-ingress   # EXTERNAL-IP, ports 80/443
```
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: blog-app-gateway
  namespace: blog-app
spec:
  selector:
    istio: ingress
  servers:
  - port: { number: 80, name: http, protocol: HTTP }
    hosts: ["*"]
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: blog-app
  namespace: blog-app
spec:
  hosts: ["*"]
  gateways: [blog-app-gateway]
  http:
  - match:
    - uri: { exact: / }
    - uri: { prefix: /static }
    - uri: { prefix: /posts }
    - uri: { exact: /login }
    - uri: { exact: /logout }
    - uri: { exact: /register }
    - uri: { exact: /updateprofile }
    route:
    - destination: { host: frontend, port: { number: 80 } }
```
Then change the `frontend` Service `type` to `ClusterIP`, commit, push, wait ~5 min for Argo CD sync. App reachable at `http://<IngressLoadBalancerExternalIP>`.

### 4. Secure the ingress with TLS (HTTPS)
Generate a self-signed root CA + server cert (use a real CA in prod):
```bash
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
  -subj '/O=example Inc./CN=example.com' -keyout example.com.key -out example.com.crt
openssl req -out blogapp.example.com.csr -newkey rsa:2048 -nodes \
  -keyout blogapp.example.com.key -subj "/CN=blogapp.example.com/O=blogapp organization"
openssl x509 -req -sha256 -days 365 -CA example.com.crt -CAkey example.com.key \
  -set_serial 1 -in blogapp.example.com.csr -out blogapp.example.com.crt
```
Store cert+key (base64) in Google Secret Manager as a new version of `external-secrets`:
```bash
echo -ne "{\"MONGO_INITDB_ROOT_USERNAME\": \"root\", \"MONGO_INITDB_ROOT_PASSWORD\": \"itsasecret\", \
\"blogapptlskey\": \"$(base64 blogapp.example.com.key -w 0)\", \
\"blogapptlscert\": \"$(base64 blogapp.example.com.crt -w 0)\"}" | \
gcloud secrets versions add external-secrets --data-file=-
```
Create an `ExternalSecret` (namespace `istio-ingress`) that renders a `kubernetes.io/tls` Secret named `blogapp-tls-credentials` (see Reference snippets). Then switch the Gateway to HTTPS:
```yaml
spec:
  selector: { istio: ingress }
  servers:
  - port: { number: 443, name: https, protocol: HTTPS }
    tls:
      mode: SIMPLE
      credentialName: blogapp-tls-credentials
    hosts: ["*"]
```
Commit/push. App then served at `https://<IngressLoadBalancerExternalIP>`.

### 5. Enforce strict mTLS inside the mesh
Default is PERMISSIVE (plaintext from non-meshed pods still works). Test then lock down:
```bash
# from a non-meshed pod (default ns) — succeeds (HTTP 200) under PERMISSIVE:
kubectl run -it --rm --image=curlimages/curl curly -- curl -v http://frontend.blog-app
```
Apply STRICT at namespace scope with `PeerAuthentication`:
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: blog-app
spec:
  mtls:
    mode: STRICT
```
After sync, the same plaintext curl now fails: `curl: (56) Recv failure: Connection reset by peer`.

### 6. Restrict service-to-service access with AuthorizationPolicy
Allow only intended callers (identified by service account principal). Implicit deny-all applies once selector matches.
```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: posts
  namespace: blog-app
spec:
  selector:
    matchLabels: { app: posts }
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/blog-app/sa/frontend"]
```
Blog App rules: `posts`/`reviews`/`users` ← `frontend`, `ratings` ← `reviews`, `mongodb` ← `posts,reviews,ratings,users` (NOT frontend). Each workload must have its own ServiceAccount set via `serviceAccountName`.
Verify from a shell in each pod with `wget`:
```bash
kubectl -n blog-app exec -it $(kubectl get pod -n blog-app | grep frontend | awk '{print $1}') -- /bin/sh
# allowed backend → HTTP 404/200 ; blocked → HTTP 403 Forbidden ; mongodb blocked → resource unavailable
```

### 7. Define versions, route, then canary
Deploy a second version (`ratings-v2`). Without DestinationRules, Istio round-robins across v1/v2 (50/50). Fix by declaring subsets and routing.
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata: { name: ratings, namespace: blog-app }
spec:
  host: ratings
  subsets:
  - { name: v1, labels: { version: v1 } }
  - { name: v2, labels: { version: v2 } }
```
Route all to v1:
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata: { name: ratings, namespace: blog-app }
spec:
  hosts: [ratings]
  http:
  - route:
    - destination: { host: ratings, subset: v1 }
```
Canary 80/20 split: full VirtualService (swap the `http.route` block above for this, the DestinationRule above is still required):
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata: { name: ratings, namespace: blog-app }
spec:
  hosts: [ratings]            # mesh-internal (east-west) routing; for an externally
                              # exposed service also set `gateways:` + public host (see Workflow 3)
  http:
  - route:
    - destination: { host: ratings, subset: v1 }
      weight: 80
    - destination: { host: ratings, subset: v2 }
      weight: 20
```
(Each non-versioned microservice gets a DestinationRule with a single `v1` subset and a VirtualService routing to it.)

> **Version note:** the book (Istio 1.19, 2024) uses `apiVersion: networking.istio.io/v1alpha3`. On current Istio that API is deprecated, emit `networking.istio.io/v1` (or `v1beta1`) for `Gateway`/`VirtualService`/`DestinationRule`. The field structure shown here is unchanged. Flag this to the user if their cluster runs a newer Istio.

### 8. Traffic mirroring (shadow testing)
Serve 100% from v1, mirror 100% of it to v2 (v2 processes but does not respond to users):
```yaml
  http:
  - route:
    - destination: { host: ratings, subset: v1 }
      weight: 100
    mirror:
      host: ratings
      subset: v2
    mirror_percent: 100
```
Verify by comparing logs (identical requests/timestamps in v1 and v2):
```bash
kubectl logs $(kubectl get pod -n blog-app | grep "ratings-"   | awk '{print $1}') -n blog-app
kubectl logs $(kubectl get pod -n blog-app | grep "ratings-v2" | awk '{print $1}') -n blog-app
```

### 9. Observability: Kiali, Grafana, Prometheus
Install add-ons via Argo CD:
```bash
mkdir ~/mdo-environments/manifests/istio-system
cp ~/modern-devops/ch15/observability/*.yaml ~/mdo-environments/manifests/istio-system/
git add --all && git commit -m "Added observability" && git push
```
Access dashboards via port-forward (Kiali on ClusterIP):
```bash
kubectl port-forward deploy/kiali   -n istio-system 20001:20001   # Kiali UI; Graph tab → blog-app ns
kubectl port-forward deploy/grafana -n istio-system 20001:3000    # Grafana → Home>Dashboards>Istio>Istio Service Dashboard
```
Kiali = real-time service interaction graph (traffic flow, success %). Grafana = SLIs (success rate, duration, size, volume, latency) + alerting via PromQL.

### 10. Alerting in Grafana
Home > Alerting > Alert rules. Example PromQL for ingress→frontend request rate (alert when > 1 tps):
```promql
round(sum(irate(istio_requests_total{connection_security_policy="mutual_tls",destination_service=~"frontend.blog-app.svc.cluster.local",reporter=~"destination",source_workload=~"istio-ingress",source_workload_namespace=~"istio-ingress"}[5m])) by (source_workload, source_workload_namespace, response_code), 0.001)
```
Demo rule: evaluate every 1 min, fire after 2 consecutive minutes of violation, trigger by refreshing the home page 15-20 times rapidly. Pending → Firing. Wire to PagerDuty/Slack for real channels (none configured by default = alerts only show in Grafana).

## Reference snippets

### ExternalSecret rendering a TLS Secret from Google Secret Manager
```yaml
apiVersion: external-secrets.io/v1alpha1
kind: ExternalSecret
metadata:
  name: blogapp-tls-credentials
  namespace: istio-ingress
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: gcp-backend
  target:
    template:
      type: kubernetes.io/tls
      data:
        tls.crt: "{{ .blogapptlscert | base64decode | toString }}"
        tls.key: "{{ .blogapptlskey | base64decode | toString }}"
    name: blogapp-tls-credentials
  data:
  - secretKey: blogapptlskey
    remoteRef: { key: external-secrets, property: blogapptlskey }
  - secretKey: blogapptlscert
    remoteRef: { key: external-secrets, property: blogapptlscert }
```

### ServiceAccount bound to a workload
```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: mongodb, namespace: blog-app }
---
apiVersion: apps/v1
kind: StatefulSet
# ...
spec:
  template:
    spec:
      serviceAccountName: mongodb
```

## Decision guidance and best practices
- **Install Istio with Helm (via Argo CD), not `istioctl`**, when doing GitOps: `istioctl` is imperative and breaks the GitOps model. (Book Q1 answer: B / Helm charts.)
- **Use Secret Manager + ExternalSecret for TLS material**: never commit private keys/certs to Git.
- **Use a real CA cert chain in production**. Self-signed is for the exercise only.
- **Roll out STRICT mTLS gradually**: default PERMISSIVE mode lets you adopt Istio incrementally before all sources are meshed. Flip to STRICT once everything is in the mesh.
- **Model least-privilege with AuthorizationPolicy + per-workload service accounts**: explicitly allow only the call paths your design requires.
- **Canary needs both `VirtualService` and `DestinationRule`** (Q5: A and C): subsets are meaningless without DestinationRule, and weights live in the VirtualService.
- **Prefer traffic mirroring over a static staging environment** for operational acceptance testing: uses real live traffic, no user impact, no costly replica env.
- **Production alerting cadence**: ~5-min check interval, ~15-min alert interval to avoid paging on transient self-resolving issues.
- **Always configure real alert channels** (PagerDuty/Slack). Grafana-only alerts get missed.
- Tool choice: **Kiali** for real-time interaction visualization (Q7: C), **Grafana** for monitoring/alerting, **Prometheus** as the telemetry store/query layer.

## Pitfalls and gotchas
- Sidecars are NOT injected retroactively. After labeling the namespace you MUST `rollout restart` existing Deployments/StatefulSets.
- Labeling the namespace alone does nothing until pods are recreated. Verify with `2/2` READY.
- Without DestinationRule subsets, a second version silently gets ~50% of traffic (round-robin), easy to mistake for a routing config.
- AuthorizationPolicy is deny-by-default once its selector matches. Forgetting a needed `ALLOW` source silently breaks calls with 403.
- Authorization principals depend on correct ServiceAccounts being assigned to each workload: missing `serviceAccountName` will misidentify the caller.
- Distinguish HTTP results when testing authz: 404/200 = allowed (reached backend), 403 = blocked by policy, "connection reset"/"resource unavailable" = blocked by mTLS/policy.
- The correct injection label is `istio-injection: enabled` (Q2 distractor `istio-injection-enabled: true` is wrong).
- The Gateway only routes if a matching VirtualService references it. A Gateway alone does nothing.
- Switch the app's frontend Service to `ClusterIP` when fronting it with the ingress gateway, else traffic bypasses the mesh via the old LoadBalancer.

## Command / API cheat-sheet
- `kubectl get svc istio-ingress -n istio-ingress`: find ingress gateway LB IP/ports.
- `kubectl rollout restart deploy/<name> -n blog-app`: recreate pods to inject sidecars.
- `kubectl run -it --rm --image=curlimages/curl curly -- curl -v http://<svc>.<ns>`: test mTLS/plaintext.
- `kubectl -n <ns> exec -it <pod> -- /bin/sh` then `wget <svc>:<port>`: test AuthorizationPolicy.
- `kubectl port-forward deploy/kiali -n istio-system 20001:20001`: Kiali dashboard.
- `kubectl port-forward deploy/grafana -n istio-system 20001:3000`: Grafana dashboard.
- `Gateway` (networking.istio.io/v1alpha3): mesh entry point: ports, hosts, TLS.
- `VirtualService` (v1alpha3): routing: path match, weight split, mirror, retries, timeouts.
- `DestinationRule` (v1alpha3): named subsets per version label.
- `PeerAuthentication` (security.istio.io/v1beta1): mTLS mode (STRICT/PERMISSIVE).
- `AuthorizationPolicy` (security.istio.io/v1beta1): allow/deny by principal/selector.
- `ExternalSecret` (external-secrets.io/v1alpha1): pull TLS material from Secret Manager.
- `istio_requests_total`: key Prometheus metric for request-rate alerts (PromQL).

## Where this is covered (topic index)
- Service mesh rationale / why Kubernetes isn't enough → Core concepts, Workflow intro.
- Istio architecture, istiod, Pilot/Citadel/Galley, data vs control plane → Core concepts.
- Envoy proxy / sidecar → Core concepts, Workflow 2.
- Install Istio with Helm + Argo CD + Terraform (GitOps) → Workflow 1.
- Sidecar injection / `istio-injection: enabled` label → Workflow 2.
- Ingress gateway, Gateway + VirtualService, exposing app → Workflow 3.
- TLS / HTTPS ingress, self-signed certs, SIMPLE mode, credentialName → Workflow 4, Reference snippet (ExternalSecret).
- mTLS, strict vs permissive, PeerAuthentication → Workflow 5, Core concepts.
- Authorization / access control / AuthorizationPolicy / principals / service accounts → Workflow 6, Reference snippet (ServiceAccount).
- Versions / subsets / DestinationRule, routing to v1 → Workflow 7.
- Canary rollout / Blue-Green / traffic shifting / weight → Workflow 7, Core concepts.
- Traffic mirroring / shadowing → Workflow 8, Core concepts.
- Observability / Kiali / Grafana / Prometheus / SLIs → Workflow 9.
- Alerting / PromQL / istio_requests_total / PagerDuty / Slack → Workflow 10.
- Secret Manager + ExternalSecret for TLS → Workflow 4, Reference snippets.
- Round-robin default behavior, fixing 50/50 split → Workflow 7, Pitfalls.
