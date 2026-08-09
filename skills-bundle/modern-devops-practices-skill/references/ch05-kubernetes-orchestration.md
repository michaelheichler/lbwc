# Chapter 05: Container Orchestration with Kubernetes

> Part 2: Container Orchestration and Serverless · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to stand up a local/dev Kubernetes cluster (Minikube or KinD), install `kubectl`, or work with the Pod resource: running pods imperatively and declaratively, troubleshooting them, adding health probes, and using multi-container patterns (init, ambassador, sidecar, adapter) with ConfigMaps and Secrets. Services, Deployments, and Ingress are deferred to Chapter 6.

## Core concepts
- **Kubernetes**: open source container orchestrator (originally Google, donated to the CNCF). Solves dynamic scheduling, horizontal autoscaling, self-healing, networking/service discovery, security isolation, and cloud integration that raw Docker does not provide for production.
- **Cluster = control plane nodes + worker nodes**. Control plane is the brain (scheduling, reconciliation). Workers run the container workloads. Everything (including internal component talk) flows through the **API server** (client-server model).
- **Desired-state reconciliation**: you declare the target state. The controller manager continuously drives actual state toward it. Deviations are auto-corrected.
- **Pod**: smallest deployable unit. Contains one or more containers that are always co-scheduled on the same node and share network/volumes. Usually one container per pod, multiple only when containers are functionally one unit.
- **Imperative vs declarative**: `kubectl run`/`create` (imperative, fast for dev) vs YAML/JSON manifests + `kubectl apply` (declarative, version-controllable, GitOps-friendly, use in staging/prod).
- **Probes**: startup (has the app started?), readiness (can it serve traffic?), liveness (is it still healthy, else kill/restart). They make pods reliable.
- **ConfigMap**: key-value store for non-sensitive config, decouples config from app. **Secret**: same idea but values are base64-encoded. Use for passwords/API keys.

## Tools and versions
- **kubectl v1.27.3**: CLI that talks to the API server. Command shape: `kubectl <verb> <resource type> <resource name> [--flags]`.
- **Minikube (latest)**: single-node (or multi-node) dev cluster. Uses your machine or containers as nodes. Requires `conntrack`. Cluster seen at v1.26.3 in the book.
- **KinD v0.20.0** (Kubernetes in Docker): runs each node as a Docker container, supports multi-node, uses **containerd** internally (no dockershim). Fast boot, ideal for CI/CD. Cluster nodes at v1.27.3. NEVER use in production (Docker-in-Docker is insecure).
- **Docker**: prerequisite host runtime (Ubuntu 18.04 Bionic LTS or later, `sudo` access).
- Book repo: `https://github.com/PacktPublishing/Modern-DevOps-Practices-2e` (chapter dir `ch5`).

## Workflows (how-to)

### Clone the chapter repo and substitute the Docker Hub placeholder
```bash
git clone https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git modern-devops
cd modern-devops/ch5
grep -rl '<your_dockerhub_user>' . | xargs sed -i -e \
  's/<your_dockerhub_user>/<your actual docker hub user>/g'
```

### Install kubectl
```bash
# Latest release
curl -LO "https://storage.googleapis.com/kubernetes-release/release\
/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)\
/bin/linux/amd64/kubectl"
# (Specific version: .../release/v<kubectl_version>/bin/linux/amd64/kubectl)
chmod +x ./kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### Install and run Minikube (single-node dev cluster)
```bash
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube
sudo mv minikube /usr/local/bin/
sudo apt-get install -y conntrack       # required package
minikube start --driver=docker
kubectl get nodes                        # minikube  Ready  control-plane
minikube stop                            # stop & remove the cluster
```

### Install KinD and bootstrap a multi-node cluster (dev / CI-CD)
```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/
kind version
```
Config file `kind-config.yaml` (1 control plane + 3 workers, add more `control-plane` items for HA):
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
```
```bash
kind create cluster --config kind-config.yaml
kubectl get nodes    # kind-control-plane + kind-worker{,2,3}, all Ready
```

### Run a pod imperatively
```bash
kubectl run nginx --image=nginx     # create
kubectl get pod                     # READY 1/1, STATUS Running
kubectl delete pod nginx            # delete
```

### Run a pod declaratively
Apply the manifest (see Reference snippets for `nginx-pod.yaml`):
```bash
kubectl apply -f nginx-pod.yaml
```
Key spec fields: `imagePullPolicy` (`Always` | `IfNotPresent` | `Never`). `resources.requests` (min to schedule) and `resources.limits` (max before eviction). `restartPolicy` (`Always` | `OnFailure` | `Never`).

### Access a pod with port-forward
```bash
kubectl port-forward nginx 8080:80    # tunnels client -> API server -> pod (encrypted)
# in another terminal:
curl 127.0.0.1:8080                   # Welcome to nginx!
```
Use port-forward ONLY for troubleshooting a pod or reaching an internal service (e.g. the dashboard). For real exposure use a `Service` (Chapter 6).

### Troubleshoot pods
```bash
kubectl logs nginx                       # logs (single container)
kubectl logs nginx -c nginx              # -c picks a container in a multi-container pod
kubectl exec -it nginx -- /bin/bash      # interactive shell
kubectl exec nginx -- ls /etc/nginx      # one-off command, no shell
kubectl describe pod nginx-1             # FIRST troubleshooting command; read Events section
```
Common failure: `STATUS ImagePullBackOff` -> `kubectl describe pod` Events shows `pull access denied, repository does not exist or may require authorization`. Fix the image, then `kubectl delete pod` and recreate. Changes made via `exec` are lost when the pod dies: diagnose only, bake fixes into a new image.

### Add and verify health probes
Apply a manifest containing the three probes (see snippet), then watch:
```bash
kubectl delete pod nginx && kubectl apply -f nginx-probe.yaml && kubectl get pod -w
# Break liveness to see auto-restart:
kubectl exec -it nginx -- rm -rf /usr/share/nginx/html/index.html && kubectl get pod nginx -w
# After ~9s (periodSeconds 3 x failureThreshold 3) container is killed & restarted by kubelet
```

### Init container pattern (e.g. fetch content before main container starts)
```bash
cd ~/modern-devops/ch5/multi-container-pod/init/
kubectl delete pod nginx && kubectl apply -f nginx-init.yaml && kubectl get pod nginx -w
# Status flow: Init:0/1 -> PodInitializing -> Running
kubectl port-forward nginx 8080:80
curl localhost:8080    # serves example.com content fetched by the init container
```

### Ambassador pattern (proxy sidecar for a remote dependency)
```bash
cd ~/modern-devops/ch5/multi-container-pod/ambassador
docker build -t <your_dockerhub_user>/flask-redis .
docker push <your_dockerhub_user>/flask-redis
kubectl run redis --image=redis
kubectl expose pod redis --port 6379          # Service so pods reach 'redis' by name
kubectl apply -f redis-config-map.yaml
kubectl apply -f nginx-config-map.yaml
kubectl apply -f flask-ambassador.yaml
kubectl get pod/flask-ambassador              # READY 2/2
kubectl port-forward flask-ambassador 5000:5000
curl localhost:5000
```
The Flask app keeps using `localhost:6379`. An nginx ambassador container listens on `localhost:6379` and TCP-proxies to the remote `redis` Service. An init container renders `nginx.conf` placeholders (`REDIS_HOST`/`REDIS_PORT`) from a ConfigMap.

### Sidecar pattern (helper container, e.g. secret-bearing Redis)
```bash
cd ~/modern-devops/ch5/multi-container-pod/sidecar
echo 'SET secret foobar' | base64           # -> U0VUIHNlY3JldCBmb29iYXIK
# build the secret-seeding redis image and the flask image:
docker build -t <your_dockerhub_user>/redis-secret .       # in sidecar/redis/
docker build -t <your_dockerhub_user>/flask-redis-secret . # in sidecar/flask/
kubectl apply -f redis-secret.yaml
kubectl apply -f flask-sidecar.yaml
kubectl get pod flask-sidecar                # READY 2/2
kubectl port-forward flask-sidecar 5000:5000
curl localhost:5000                          # Hi there! The secret is foobar.
```

### Adapter pattern (transform/standardize log output)
```bash
kubectl apply -f app-adapter.yaml
kubectl get pod app-adapter                  # READY 2/2
kubectl exec -it app-adapter -c log-adapter -- bash
# app.log = raw lines; out.log = same lines with [timestamp] prepended
```

## Reference snippets

### Pod manifest with resource requests/limits (`nginx-pod.yaml`)
```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: nginx
  name: nginx
spec:
  containers:
  - image: nginx
    imagePullPolicy: Always
    name: nginx
    resources:
      limits:
        memory: "200Mi"
        cpu: "200m"
      requests:
        memory: "100Mi"
        cpu: "100m"
  restartPolicy: Always
```

### Pod probes (`nginx-probe.yaml`, spec.containers excerpt)
```yaml
    startupProbe:
      exec:
        command:
        - cat
        - /usr/share/nginx/html/index.html
      failureThreshold: 30
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
    livenessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 3
  restartPolicy: Always
```

### Init container with shared emptyDir volume (`nginx-init.yaml`, spec excerpt)
```yaml
spec:
  containers:
  - name: nginx-container
    image: nginx
    volumeMounts:
    - mountPath: /usr/share/nginx/html
      name: html-volume
  initContainers:
  - name: init-nginx
    image: busybox:1.28
    command: ['sh', '-c', 'mkdir -p /usr/share/nginx/html && wget -O /usr/share/nginx/html/index.html http://example.com']
    volumeMounts:
    - mountPath: /usr/share/nginx/html
      name: html-volume
  volumes:
  - name: html-volume
    emptyDir: {}
```

### ConfigMaps for the ambassador pattern
```yaml
# redis-config-map.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
data:
  host: "redis"
  port: "6379"
---
# nginx-config-map.yaml (TCP reverse proxy template)
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    stream {
        server {
            listen     6379;
            proxy_pass stream_redis_backend;
        }
        upstream stream_redis_backend {
            server REDIS_HOST:REDIS_PORT;
        }
    }
```

### Ambassador pod with init-rendered config (`flask-ambassador.yaml`)
```yaml
spec:
  containers:
  - name: flask-app
    image: <your_dockerhub_user>/flask-redis
  - name: nginx-ambassador
    image: nginx
    volumeMounts:
    - mountPath: /etc/nginx
      name: nginx-volume
  initContainers:
  - name: init-nginx
    image: busybox:1.28
    command: ['sh', '-c', 'cp -L /config/nginx.conf /etc/nginx/nginx.conf && sed -i "s/REDIS_HOST/${REDIS_HOST}/g" /etc/nginx/nginx.conf']
    env:
      - name: REDIS_HOST
        valueFrom:
          configMapKeyRef:
            name: redis-config
            key: host
      - name: REDIS_PORT
        valueFrom:
          configMapKeyRef:
            name: redis-config
            key: port
    volumeMounts:
    - mountPath: /etc/nginx
      name: nginx-volume
    - mountPath: /config
      name: config
  volumes:
  - name: nginx-volume
    emptyDir: {}
  - name: config
    configMap:
      name: nginx-config
      items:
      - key: "nginx.conf"
        path: "nginx.conf"
```

### Secret + sidecar pod (`redis-secret.yaml`, `flask-sidecar.yaml`)
```yaml
# redis-secret.yaml  (data values are base64-encoded)
apiVersion: v1
kind: Secret
metadata:
  name: redis-secret
data:
  redis-secret: U0VUIHNlY3JldCBmb29iYXIK
---
# flask-sidecar.yaml (spec excerpt)
spec:
  containers:
  - name: flask-app
    image: <your_dockerhub_user>/flask-redis-secret
  - name: redis-sidecar
    image: <your_dockerhub_user>/redis-secret
    volumeMounts:
    - mountPath: /redis-master
      name: secret
  volumes:
  - name: secret
    secret:
      secretName: redis-secret
      items:
      - key: redis-secret
        path: init.redis
```
Secret-seeding Redis image (`entrypoint.sh` + Dockerfile):
```bash
redis-server --daemonize yes && sleep 5
redis-cli < /redis-master/init.redis
redis-cli save
redis-cli shutdown
redis-server
```
```dockerfile
FROM redis
COPY entrypoint.sh /tmp/
CMD ["sh", "/tmp/entrypoint.sh"]
```

### Adapter pod (`app-adapter.yaml`, spec excerpt)
```yaml
spec:
  volumes:
  - name: logs
    emptyDir: {}
  containers:
  - name: app-container
    image: ubuntu
    command: ["/bin/bash"]
    args: ["-c", "while true; do echo 'This is a log line' >> /var/log/app.log; sleep 2;done"]
    volumeMounts:
    - name: logs
      mountPath: /var/log
  - name: log-adapter
    image: ubuntu
    command: ["/bin/bash"]
    args: ["-c", "apt update -y && apt install -y moreutils && tail -f /var/log/app.log | ts '[%Y-%m-%d %H:%M:%S]' > /var/log/out.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log
```

## Decision guidance and best practices
- **Declarative in staging/prod, imperative in dev**: manifests version in Git and enable GitOps. Imperative `kubectl run` is fine for quick local turnaround.
- **Set `imagePullPolicy: IfNotPresent`** unless you have a strong reason for `Always`/`Never`: faster boots, fewer needless downloads.
- **Always set resource requests and limits**. Consider a cluster-level default policy so a missing block can't exhaust node resources.
- **Use readiness + liveness probes together** for resilience: readiness keeps traffic off not-ready pods. Liveness restarts deadlocked/unhealthy containers. Use a startup probe for slow-starting apps (it suppresses the others until the app is up).
- **Multi-container pods only when containers are functionally one unit.** Patterns: ambassador (proxy for an external dependency, decouples app from config), sidecar (logging/monitoring/secret helpers, decoupled from main), adapter (normalize output for a downstream tool), init (one-time setup before main starts).
- **Init containers as last resort**: they slow pod startup. Prefer baking config into the image.
- **Secrets for confidential data, ConfigMaps for non-sensitive config.** Mount secrets into a sidecar rather than the app container so a filesystem compromise of the app doesn't expose them.
- **Bake the runtime user into the image** rather than relying on `securityContext.runAsUser`. Never default to root.
- **Use a managed K8s service or `kubeadm` for real clusters**. Minikube/KinD are dev/CI only.

## Pitfalls and gotchas
- **KinD is never for production**: Docker-in-Docker is insecure.
- **`exec` edits are ephemeral**: files added or packages installed inside a running container vanish when the pod restarts. Only diagnose, then rebuild the image.
- **`emptyDir` volumes are not persistent** (like Docker `tmpfs`). They live only for the pod's lifetime.
- **base64 is not encryption**: Secret values are merely base64-encoded, no better than plaintext security-wise. Treat them as such.
- **`ImagePullBackOff`** usually means a typo'd, nonexistent, or private/unauthorized image: confirm via `kubectl describe pod` Events.
- **Liveness false positives**: too-aggressive `periodSeconds`/`failureThreshold` will kill healthy-but-slow containers. Tune relative to real start/response times.
- **port-forward is not for public exposure**: it tunnels through the local kubectl client and API server only.
- Distroless images block `exec` by design. Use their debug variant when you must get a shell.

## Command / API cheat-sheet
- `kubectl version --client`: print client version.
- `kubectl get nodes` / `kubectl get pod [-w]`: list nodes / pods (`-w` to watch).
- `kubectl run <name> --image=<img>`: imperatively create a pod.
- `kubectl apply -f <file>.yaml`: declaratively create/update resources.
- `kubectl delete pod <name>`: delete a pod.
- `kubectl describe pod <name>`: detailed status + Events (first troubleshooting step).
- `kubectl logs <pod> [-c <container>]`: container logs.
- `kubectl exec -it <pod> [-c <container>] -- <cmd>`: run command / shell in a container.
- `kubectl port-forward <pod> <local>:<remote>`: tunnel a local port to a pod port.
- `kubectl expose pod <name> --port <p>`: create a Service for a pod (detail in Ch6).
- `minikube start --driver=docker` / `minikube stop`: start/stop single-node dev cluster.
- `kind create cluster --config <file>` / `kind version`: multi-node container-based cluster.
- API objects: `Pod`, `ConfigMap`, `Secret` (`v1`), KinD `Cluster` (`kind.x-k8s.io/v1alpha4`).

## Where this is covered (topic index)
- Why orchestration / what K8s solves -> Core concepts, "What is Kubernetes" intro.
- Control plane components (API server, controller manager, etcd, scheduler, cloud controller manager) -> Core concepts, architecture.
- Worker components (kubelet: only systemd service, kube-proxy) -> Core concepts.
- Install kubectl -> Workflows "Install kubectl".
- Minikube setup / single-node dev cluster -> Workflows "Install and run Minikube".
- KinD / Kubernetes in Docker / multi-node / CI-CD cluster / containerd -> Workflows "Install KinD".
- Pod basics / run a pod / imperative vs declarative -> Workflows "Run a pod ...".
- Pod manifest fields / requests / limits / restartPolicy / imagePullPolicy -> Reference `nginx-pod.yaml`.
- Accessing a pod / port-forward -> Workflows "Access a pod with port-forward".
- logs / exec / describe / ImagePullBackOff / debugging -> Workflows "Troubleshoot pods".
- Probes (startup, readiness, liveness) / health checks / self-heal -> Workflows + `nginx-probe.yaml`.
- Init containers -> Workflows + `nginx-init.yaml`.
- Ambassador pattern / proxy / ConfigMap -> Workflows + ambassador snippets.
- Sidecar pattern / Secret / base64 -> Workflows + sidecar snippets.
- Adapter pattern / log transformation -> Workflows + `app-adapter.yaml`.
- ConfigMap vs Secret guidance -> Decision guidance.
- emptyDir volumes -> Reference snippets, Pitfalls.
- Services / Deployments / Ingress -> not here, deferred to Chapter 6.
