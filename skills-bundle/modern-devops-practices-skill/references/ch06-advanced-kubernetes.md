# Chapter 06: Managing Advanced Kubernetes Resources

> Part 2: Container Orchestration and Serverless · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to deploy and manage workloads on Kubernetes beyond raw pods: creating Deployments with rollout/rollback strategies, exposing apps via Services or Ingress, autoscaling with HPA, or running stateful apps with StatefulSets + PersistentVolumes. Also the source for `kubectl` aliases and dry-run manifest generation.

## Core concepts
- **Why pods aren't enough**: bare pods don't replicate, auto-heal, version, roll out/back, autoscale, expose externally, or persist data. Advanced resources (Deployment, Service, Ingress, PV/PVC, StatefulSet, HPA) solve these.
- **ReplicaSet**: controller that keeps N pod replicas running, recreates pods that die. Never use directly, it's the backend of a Deployment.
- **Deployment**: manages stateless workloads via ReplicaSets. Provides versioning, rolling updates, rollback, scaling. Each update creates a new ReplicaSet (old one is kept and scaled to 0, NOT deleted, enabling fast rollback).
- **Service**: gives a stable static IP + FQDN to a group of pods (selected by labels) and load-balances traffic round-robin. Pods are ephemeral (IP/hostname change), so you target the Service, not pods. FQDN form: `<service_name>.<namespace>.svc.<cluster-domain>.local`.
- **Service types**: `ClusterIP` (internal only, default), `NodePort` (exposes on a high port 30000-32767 on every node), `LoadBalancer` (cloud LB in front of NodePort, single external endpoint).
- **Ingress**: reverse proxy / L7 router into the cluster. One load balancer routes to many Services by URL path or hostname. Requires an ingress controller.
- **HorizontalPodAutoscaler (HPA)**: scales ReplicaSet replicas based on metrics (CPU/memory percentage of pod resource limits, or external metrics). Requires resource limits set on the pod.
- **StatefulSet**: like a Deployment but for stateful apps. Pods get ordered numeric names (not random hashes), sticky identity, ordered rollout/scale-in, and each pod keeps its own volume across restarts. Requires a headless Service + PersistentVolumes.
- **PersistentVolume (PV) / PersistentVolumeClaim (PVC) / StorageClass**: PV is a storage resource, PVC claims it, StorageClass enables dynamic provisioning. Static = admin pre-creates disk+PV, dynamic = Kubernetes asks the cloud for storage via a StorageClass.
- **Namespaces**: virtual clusters within one physical cluster to segregate resources by team/project. Default namespace used throughout.

## Tools and versions
- **GKE (Google Kubernetes Engine)**: cloud cluster used for the whole chapter (local KinD/MiniKube cannot create LoadBalancers or cloud PersistentVolumes). GCP free $300/90-day trial.
- **kubectl**: primary CLI.
- **nginx ingress controller** `controller-v1.8.0` (github.com/kubernetes/ingress-nginx): chosen over native GKE controller to stay cloud-agnostic.
- **hey**: load-testing utility (preinstalled in Google Cloud Shell) for HPA testing.
- Node version in examples: `v1.26.15-gke.4901`.
- Exercise files: clone `github.com/PacktPublishing/Modern-DevOps-Practices-2e`, work in `ch6/` subdirs (`deployments/`, `services/`, `statefulsets/`).

## Workflows (how-to)

### Spin up the GKE cluster + clone repo
```bash
gcloud services enable container.googleapis.com
gcloud container clusters create cluster-1 --zone us-central1-a
git clone https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git modern-devops
cd modern-devops/ch6
```

### Create and manage a Deployment
```bash
kubectl apply -f nginx-deployment.yaml
kubectl get deployment            # READY / UP-TO-DATE / AVAILABLE
kubectl get replicaset            # Deployment creates a hashed RS
kubectl get pod                   # pods = <rs-name>-<hash>

# Update image (imperative)
kubectl set image deployment/nginx nginx=nginx:1.16.1
kubectl rollout status deployment nginx

# Record change-cause (always annotate — see tip)
kubectl annotate deployment nginx kubernetes.io/change-cause="Updated nginx version to 1.16.1" --overwrite=true

kubectl rollout history deployment nginx     # list revisions + CHANGE-CAUSE
kubectl rollout undo deployment nginx         # roll back to previous revision
```

### Choose a Deployment strategy
Built-in: `Recreate` and `RollingUpdate` (default). Derived/external: Blue/Green, Canary, A/B (A/B needs a service mesh, Istio, Linkerd, or Traefik).

- **Recreate**: scales old RS to 0, then brings up new RS. Causes downtime. Use only when the app cannot run multiple replicas or multiple versions simultaneously (e.g. quorum-based apps).
  ```yaml
  spec:
    replicas: 3
    strategy:
      type: Recreate
  ```
- **RollingUpdate**: new RS scales up while old scales down simultaneously, no downtime. Knobs `maxSurge` (max extra pods) and `maxUnavailable` (max unavailable pods). Cannot set both to 0.
  - **Ramped slow rollout** (cautious, slow): `maxSurge: 1`, `maxUnavailable: 0`, total never exceeds replicas+1.
  - **Best-effort controlled rollout** (fast, no extra capacity): `maxSurge: 0`, `maxUnavailable: 25%`, prefer a percentage so you don't recompute when replicas change.

### Expose pods with a Service
```bash
# ClusterIP (internal, default)
kubectl create deployment redis --image=redis
kubectl apply -f redis-clusterip.yaml
kubectl get service redis

# Test from inside the cluster
kubectl run busybox --rm --restart Never -it --image=busybox
/ # telnet redis 6379                 # same namespace -> service name
/ # telnet redis.default 6379         # cross-namespace -> service.namespace
/ # nslookup 10.96.118.99             # reverse-resolves to redis.default.svc.cluster.local

# NodePort (maps container port to a high node port)
kubectl apply -f flask-nodeport.yaml
kubectl get service flask-app          # 5000:32618/TCP
gcloud compute ssh gke-node-1dhh
$ curl localhost:32618

# LoadBalancer (cloud external IP)
kubectl apply -f flask-loadbalancer.yaml
kubectl get svc flask-app              # shows EXTERNAL-IP
curl <EXTERNAL-IP>:5000
```

### Set up Ingress (nginx controller on GKE)
```bash
# Install the nginx ingress controller (creates ingress-nginx namespace)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.0/deploy/static/provider/cloud/deploy.yaml

# Re-expose target as ClusterIP, then create the Ingress
kubectl apply -f flask-clusterip.yaml
kubectl apply -f flask-basic-ingress.yaml
kubectl get ingress flask-app

# Get the external IP to hit (the controller's LB Service)
kubectl get svc ingress-nginx-controller -n ingress-nginx
curl <ingress-controller-external-ip>
```
Note: Ingress rules take a few minutes to propagate, retry after ~5 min if you get an error.

For **path-based** routing, create the two backends and apply the path Ingress. For **name-based** routing, add a `/etc/hosts` entry so the host headers resolve:
```bash
kubectl run nginx-v1 --image=bharamicrosystems/nginx:v1
kubectl run nginx-v2 --image=bharamicrosystems/nginx:v2
kubectl expose pod nginx-v1 --port=80
kubectl expose pod nginx-v2 --port=80
kubectl apply -f nginx-app-path-ingress.yaml
curl <ip>/v1/    # This is version 1
curl <ip>/v2/    # This is version 2

# name-based
kubectl apply -f nginx-app-host-ingress.yaml
# add to /etc/hosts:  <Ingress_External_IP> v1.example.com v2.example.com
curl v1.example.com
curl v2.example.com
```

### Horizontal Pod autoscaling
Resource limits on the pod are mandatory: HPA scales on % of those limits.
```bash
kubectl apply -f nginx-autoscale-deployment.yaml          # pod has cpu/memory limits
kubectl expose deployment nginx --port 80 --type LoadBalancer
kubectl get svc nginx                                      # grab EXTERNAL-IP

# min 1, max 5 replicas, target 25% avg CPU
kubectl autoscale deployment nginx --cpu-percent=25 --min=1 --max=5

# Watch (separate shells)
kubectl get deployment nginx -w
kubectl get hpa nginx -w

# Load test (hey: 120s, 100 concurrent)
hey -z 120s -c 100 http://<EXTERNAL-IP>
```
HPA scales up as CPU exceeds target (2 → 4 → 5) and gradually scales down to min after load stops.

### Stateful app: static provisioning
```bash
cd ~/modern-devops/ch6/statefulsets/
# 1. Manually create cloud disk in the SAME zone as the cluster
gcloud compute disks create nginx-manual --size 50GB --type pd-ssd --zone us-central1-a
# 2. Create PV, headless Service, then StatefulSet
kubectl apply -f nginx-manual-pv.yaml
kubectl apply -f nginx-manual-service.yaml
kubectl apply -f nginx-manual-statefulset.yaml
# 3. Verify binding
kubectl get pvc      # html-nginx-manual-0 Bound -> nginx-manual-pv
kubectl get pv       # STATUS Bound
kubectl get pod      # nginx-manual-0  (ordered numeric name)
# 4. Prove persistence: write a file, delete pod, file survives
kubectl exec -it nginx-manual-0 -- /bin/bash
  echo 'Hello, world' > /usr/share/nginx/html/index.html
kubectl delete pod nginx-manual-0
kubectl exec -it nginx-manual-0 -- cat /usr/share/nginx/html/index.html  # still there
```

### Stateful app: dynamic provisioning
```bash
kubectl apply -f fast-storage-class.yaml
kubectl apply -f nginx-dynamic-service.yaml
kubectl apply -f nginx-dynamic-statefulset.yaml
kubectl get pvc      # Bound, STORAGECLASS=fast
kubectl get pv       # dynamically created pvc-xxxx, RECLAIM POLICY Delete
```
The dynamic StatefulSet differs from static by adding `storageClassName: "fast"` in `volumeClaimTemplates` and dropping the label `selector`.

### kubectl productivity
```bash
alias k='kubectl'
alias kdr='kubectl --dry-run=client -o yaml'
alias kap='kubectl apply -f'
alias kad='kubectl delete -f'
alias kbb='kubectl run busybox-test --image=busybox -it --rm --restart=Never --'
alias kgp='kubectl get pods'; alias kgn='kubectl get nodes'; alias kgs='kubectl get svc'
alias kdb='kubectl describe'; alias kl='kubectl logs'; alias ke='kubectl exec -it'

# Generate a manifest skeleton from an imperative command (creates nothing)
kubectl run nginx --image=nginx --dry-run=client -o yaml
kdr create deployment nginx --image=nginx

# Enable bash autocompletion
echo "source <(kubectl completion bash)" >> ~/.bashrc
```
`--dry-run` works for most resources. For ones with no imperative command (e.g. `DaemonSet`) generate the closest (`Deployment`) and edit.

## Reference snippets

### Deployment (RollingUpdate is implicit default)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
```

### ClusterIP Service
```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: redis
  name: redis
spec:
  ports:
  - port: 6379
    protocol: TCP
    targetPort: 6379
  selector:
    app: redis
```
NodePort / LoadBalancer = same manifest plus `type: NodePort` or `type: LoadBalancer` in `spec`.

### Ingress: path-based routing
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-app
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - http:
      paths:
      - path: /v1
        pathType: Prefix
        backend:
          service:
            name: nginx-v1
            port:
              number: 80
      - path: /v2
        pathType: Prefix
        backend:
          service:
            name: nginx-v2
            port:
              number: 80
```

### Ingress: name-based (host) routing
```yaml
spec:
  rules:
  - host: v1.example.com
    http:
      paths:
      - path: "/"
        pathType: Prefix
        backend:
          service: { name: nginx-v1, port: { number: 80 } }
  - host: v2.example.com
    http:
      paths:
      - path: "/"
        pathType: Prefix
        backend:
          service: { name: nginx-v2, port: { number: 80 } }
```

### PersistentVolume (static, GCE disk)
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nginx-manual-pv
  labels:
    usage: nginx-manual-disk
spec:
  capacity:
    storage: 50G
  accessModes:
    - ReadWriteOnce
  gcePersistentDisk:
    pdName: nginx-manual
    fsType: ext4
```
Access modes: `ReadWriteOnce` (one pod RW), `ReadOnlyMany` (many RO), `ReadWriteMany` (many RW). Not all storage supports all modes.

### Headless Service (required by StatefulSet)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-manual
  labels:
    app: nginx-manual
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None          # makes it headless -> DNS resolves to pods
  selector:
    app: nginx-manual
```

### StatefulSet (static PV via label selector)
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: nginx-manual
spec:
  selector:
    matchLabels:
      app: nginx-manual
  serviceName: "nginx-manual"
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx-manual
    spec:
      containers:
      - name: nginx
        image: nginx
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: html
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 40Gi
      selector:
        matchLabels:
          usage: nginx-manual-disk
```

### StorageClass (dynamic, GCP SSD)
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-ssd
```
Dynamic StatefulSet `volumeClaimTemplates` uses `storageClassName: "fast"` and omits the label `selector`.

## Decision guidance and best practices
- **Service type**: always start with `ClusterIP`. Only widen to NodePort/LoadBalancer/Ingress when needed, so you don't accidentally expose internals.
- **Avoid LoadBalancer for HTTP**: each LB Service spins up a (costly) network load balancer. Use Ingress for HTTP, it shares one application LB across many Services.
- **NodePort is intermediate**: rarely used standalone. On cloud use LoadBalancer. On-prem prefer Ingress over NodePort-per-Service.
- **Don't hardcode NodePort numbers**: causes port conflicts and config-management dependency, use dynamic ports.
- **Always annotate Deployment updates** (`kubernetes.io/change-cause`) so `rollout history` is meaningful. Prefer declarative manifests in Git over imperative commands (audit trail).
- **Rollout knobs**: `maxSurge: 0` if app can't exceed a replica count. `maxUnavailable: 0` if you need full availability and can tolerate extra pods (needs spare cluster capacity). Use percentages for `maxUnavailable`.
- **Recreate strategy** only for apps that can't run multiple versions/replicas (e.g. quorum apps), accepts downtime.
- **HPA metrics**: combine CPU/memory with external metrics (response time, network latency) for reliability, those map directly to customer experience.
- **StatefulSet over Deployment** for any workload that must persist state or needs stable identity/ordering.
- **Generic StorageClass names** (`fast`, `standard`, `block`, `shared`): never cloud-specific names. PVCs reference them and you'd have to rewrite manifests on cloud migration.
- **Prefer dynamic over static provisioning** for DevOps-friendly orgs (no manual disk tracking). Static suits orgs that keep a hard Dev/Ops line.
- **Shortest possible service domain names** in endpoints: gives flexibility when moving resources across environments.
- **Always set a `template`** in a ReplicaSet: without it, it can't create new pods.

## Pitfalls and gotchas
- Updating a Deployment image does NOT delete the old ReplicaSet: it scales it to 0 (chapter Q1 answer: False). This is intentional, for fast rollback.
- ReplicaSets must never be used directly. They're meant only as Deployment backends.
- HPA does nothing without pod resource limits: it has no denominator to compute a CPU/memory percentage.
- LoadBalancer and cloud PersistentVolumes don't work on local KinD/MiniKube: you need a cloud cluster (GKE here).
- StatefulSet requires BOTH a headless Service (`clusterIP: None`) and a volume source (PV or StorageClass). Pods won't get stable network identity otherwise.
- Create the cloud disk in the same zone as the cluster, or the PV won't attach.
- Ingress rule propagation takes minutes: initial curls may fail, wait ~5 min.
- Ingress only handles HTTP(S) workloads (not raw TCP/FTP/SMTP, chapter Q answer: HTTP only).
- Setting both `maxSurge` and `maxUnavailable` to 0 makes any rollout impossible.

## Command / API cheat-sheet
- `kubectl apply -f <manifest>`: declaratively create/update a resource.
- `kubectl set image deployment/<name> <c>=<img>`: imperatively update a Deployment image.
- `kubectl rollout status|history|undo deployment <name>`: track / view / roll back a rollout.
- `kubectl annotate deployment <name> kubernetes.io/change-cause="..." --overwrite=true`: record rollout reason.
- `kubectl get replicaset|deployment|pod|svc|ingress|pv|pvc|hpa`: list resources.
- `kubectl expose deployment <name> --port <p> --type LoadBalancer`: create a Service imperatively.
- `kubectl autoscale deployment <name> --cpu-percent=N --min=N --max=N`: create an HPA.
- `kubectl run <name> --image=<img> [-it --rm --restart=Never]`: run a one-off / test pod.
- `kubectl exec -it <pod> -- <cmd>`: shell into a pod.
- `kubectl <verb> <res> --dry-run=client -o yaml`: generate a manifest without creating.
- `gcloud container clusters create <name> --zone <z>`: create GKE cluster.
- `gcloud compute disks create <name> --size <n>GB --type pd-ssd --zone <z>`: create cloud disk for a static PV.
- Resources: `Deployment`, `ReplicaSet`, `Service` (ClusterIP/NodePort/LoadBalancer), `Ingress`, `HorizontalPodAutoscaler`, `StatefulSet`, `PersistentVolume`, `PersistentVolumeClaim`, `StorageClass`, `DaemonSet`.

## Where this is covered (topic index)
- ReplicaSet / replicas / self-healing -> "Core concepts", Deployment workflow.
- Deployment, rollout, rollback, revision, change-cause -> "Create and manage a Deployment".
- Deployment strategies / Recreate / RollingUpdate / maxSurge / maxUnavailable / canary / blue-green / A/B / ramped / best-effort -> "Choose a Deployment strategy".
- Service / ClusterIP / NodePort / LoadBalancer / FQDN / service discovery / DNS / nslookup -> "Expose pods with a Service".
- Headless service / clusterIP None -> "Headless Service" snippet + StatefulSet workflow.
- Ingress / ingress controller / nginx-ingress / reverse proxy / path-based routing / name-based (host) routing / /etc/hosts -> "Set up Ingress".
- HPA / autoscaling / cpu-percent / hey load test / resource limits -> "Horizontal Pod autoscaling".
- StatefulSet / stateful / sticky identity / ordered pods -> "Stateful app" workflows + StatefulSet snippet.
- PersistentVolume / PVC / access modes / ReadWriteOnce / ReadOnlyMany / ReadWriteMany / static provisioning -> "static provisioning" workflow + PV snippet.
- StorageClass / dynamic provisioning / provisioner / pd-ssd -> "dynamic provisioning" workflow + StorageClass snippet.
- Namespaces -> "Core concepts".
- kubectl aliases / dry-run / bash autocompletion / busybox / k / kdr / kap -> "kubectl productivity".
- GKE / gcloud / cluster creation -> "Spin up the GKE cluster".
