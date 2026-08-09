# Chapter 03: Containerization with Docker

> Part 1: Modern DevOps Fundamentals · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when installing/configuring Docker on Ubuntu, running and troubleshooting containers, choosing storage drivers or persistence options, wiring up Docker logging drivers (journald/Splunk/json-file), monitoring containers with Prometheus + cAdvisor + node exporter, or declaratively running multi-container apps with Docker Compose.

## Core concepts
- **Container**: a process (not a mini-VM) running on a host, built from a layered image that bundles app files, libraries, and dependencies. Treat each container as its own entity. Never map it to a specific VM for logging/monitoring purposes.
- **Image / tag / digest**: containers are instantiated from images on a registry (Docker Hub by default). If no tag is supplied, Docker assumes `:latest`. Images are layered and usually derived from base images.
- **Ephemeral filesystem**: the writable container layer is wiped when the container is deleted. It talks to the host FS through a **storage driver**, which is slower than direct host writes. Use volumes/bind mounts/tmpfs for persistence and performance.
- **Daemon vs short-lived process**: `nginx` is a long-running daemon (blocks the terminal in the foreground). `hello-world` prints and exits. Run daemons detached with `-d`.
- **Logging model**: containers write to `stdout`/`stderr`. Docker's **logging driver** exports those logs to a destination. Default driver is `json-file`.
- **Imperative vs declarative**: typing `docker run ...` is imperative. **Docker Compose** is declarative: you declare desired state in a YAML file and `docker compose up` reconciles it. Declarative management enables GitOps for Docker workloads.
- **Registry options**: Docker Hub (public + private repos), or self-host via Google Container Registry (GCR), Sonatype Nexus, or JFrog Artifactory. The mechanism is the same.

## Tools and versions
- **OS**: Ubuntu 22.04 Jammy Jellyfish (18.04 Bionic LTS or later supported). Sudo access required.
- **Docker Engine**: `docker-ce` (book shows `Docker version 24.0.2, build cb74dfc`). Installed with CLI, containerd.io, buildx plugin, and compose plugin.
- **Docker Compose**: installed as the `docker-compose-plugin` (use `docker compose`, the v2 subcommand).
- **Prometheus**: free open-source monitoring with PromQL, time-series DB, exporters, alerting. Installed via book's `prometheus_setup.sh`.
- **cAdvisor** (`google/cadvisor:latest`): scrapes per-container metrics, exposes on port 8080.
- **node exporter**: exposes host node metrics on port 9100 (installed via `node_exporter_setup.sh`).
- **BusyBox**: lightweight shell container for troubleshooting/debugging (mostly network issues).
- **Apache Bench (`ab`)**: HTTP load-testing tool used to drive metric spikes.
- **Book GitHub repo**: https://github.com/PacktPublishing/Modern-DevOps-Practices-2e (chapter files under `ch3/`).

## Workflows (how-to)

### Install Docker on Ubuntu
1. Install HTTPS support tools so apt can fetch Docker:
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
```
2. Add Docker's GPG key:
```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```
3. Add the Docker apt repository:
```bash
echo \
  "deb [arch="$(dpkg --print-architecture)" \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" \
  stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```
4. Install the engine + plugins:
```bash
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli \
  containerd.io docker-buildx-plugin docker-compose-plugin
```
5. Verify and grant a non-root user access (log out/in to apply):
```bash
sudo docker --version
sudo usermod -a -G docker <username>
docker run hello-world
```
For non-Ubuntu OSes see https://docs.docker.com/engine/install/.

### Configure the storage driver (overlay2 vs devicemapper)
1. Check the current driver:
```bash
docker info | grep 'Storage Driver'   # -> Storage Driver: overlay2
```
2. To change it, edit `/etc/docker/daemon.json`:
```json
{
  "storage-driver": "overlay2"
}
```
3. Restart and verify:
```bash
sudo systemctl restart docker
sudo systemctl status docker
docker info | grep 'Storage Driver'
```
`overlay2` is the default/recommended on all OSes except RHEL 7 / CentOS 7 and older. Setting `devicemapper` produces deprecation warnings. WARNING: changing the storage driver wipes existing containers and local images. Take downtime and re-pull images.

### Run your first container
General form: `docker run [OPTIONS] IMAGE[:TAG|@DIGEST] [COMMAND] [ARG...]`
```bash
docker run hello-world                  # no tag -> :latest, pulled from Docker Hub
docker run nginx:1.18.0                  # versioned image; nginx is a daemon -> blocks terminal
docker run -d nginx:1.18.0              # detached/background; prints container ID
```

### Troubleshoot / inspect containers
```bash
docker ps                               # running containers (note ID + auto name like fervent_shockley)
docker ps -a                            # include stopped containers
docker logs <container_id|name>         # view stdout/stderr logs (used ~90% of the time)
```
BusyBox for debugging (especially network issues):
```bash
docker run busybox echo 'Hello World!'
docker run -it --rm busybox /bin/sh     # interactive shell; --rm auto-cleans on exit
```

### Run a production-grade NGINX container
```bash
docker run -d --name nginx --restart unless-stopped \
  -p 80:80 --memory 1000M --memory-reservation 250M nginx:1.18.0
curl localhost:80                        # NGINX welcome page
```
Flags: `-d` detached · `--name` fixed name · `--restart unless-stopped` (restart on failure + on daemon start, but respect manual stop, other values are `no`, `on_failure`, `always`) · `-p 80:80` host→container port forward · `--memory 1000M` hard limit (container stops + obeys `--restart` if exceeded) · `--memory-reservation 250M` soft limit when host runs low.

### Stop / start / remove containers
```bash
docker stop nginx
docker start nginx
docker stop nginx && docker rm nginx
docker rm -f nginx                       # stop + remove in one step
```

### Configure a logging driver
1. Check current driver:
```bash
docker info | grep "Logging Driver"     # default: json-file
```
2. Set default in `/etc/docker/daemon.json`, then `sudo systemctl restart docker`.
   - journald:
```json
{ "log-driver": "journald" }
```
   - Splunk:
```json
{
  "log-driver": "splunk",
  "log-opts": {
    "splunk-token": "<Splunk HTTP Event Collector token>",
    "splunk-url": "<Splunk HTTP(S) url>"
  }
}
```
3. View logs:
```bash
docker run --name nginx-journald -d nginx
sudo journalctl CONTAINER_NAME=nginx-journald
```
4. Override the default per-container (e.g. force json-file while default is Splunk):
```bash
docker run --name nginx-json-file --log-driver json-file -d nginx
cat /var/lib/docker/containers/<container_id>/<container_id>-json.log
```

### Monitor containers with Prometheus + cAdvisor + node exporter
1. On the Prometheus machine (separate Ubuntu 22.04 host):
```bash
git clone https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git modern-devops
cd modern-devops/ch3/prometheus/
sudo bash prometheus_setup.sh
sudo systemctl status prometheus
```
2. On the Docker host, run cAdvisor (port 8080) and the node exporter (port 9100):
```bash
docker run -d --restart always --name cadvisor -p 8080:8080 \
  -v "/:/rootfs:ro" -v "/var/run:/var/run:rw" -v "/sys:/sys:ro" \
  -v "/var/lib/docker/:/var/lib/docker:ro" google/cadvisor:latest

cd ~/modern-devops/ch3/prometheus/
sudo bash node_exporter_setup.sh
```
3. On the Prometheus machine, add scrape jobs to `/etc/prometheus/prometheus.yml`, then restart:
```yaml
  - job_name: 'node_exporter'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9100', '<Docker_IP>:9100']
  - job_name: 'Docker Containers'
    static_configs:
      - targets: ['<Docker_IP>:8080']
```
```bash
sudo systemctl restart prometheus
```
4. Launch a workload, load-test it, and query in the Prometheus UI (`https://<PROMETHEUS_IP>:9090`):
```bash
docker run -d --name web -p 8081:80 nginx
ab -n 100000 http://localhost:8081/      # Apache Bench: 100k requests to spike memory
```
PromQL examples:
```promql
container_memory_usage_bytes{name=~"web"}
node_cpu{instance="<Docker_IP>:9100",job="node_exporter"}
```

### Deploy a multi-container app with Docker Compose
```bash
git clone https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git modern-devops
cd modern-devops/ch3/docker-compose
docker compose up -d        # builds/pulls images, creates network+volume, starts containers
docker ps                   # flask on 0.0.0.0:80->5000/tcp; redis internal (6379, no mapping)
curl localhost              # "Hi there! This page was last visited on ..."
docker compose restart redis  # data persists via the redis-data volume
```
The Flask app connects to Redis by the **service name** `redis` because both share the `flask-app-net` bridge network (services on the same Compose network resolve each other by name).

## Reference snippets

### docker-compose.yaml (Flask + Redis)
```yaml
version: "2.4"
services:
  flask:
    image: "bharamicrosystems/python-flask-redis:latest"
    ports:
      - "80:5000"
    networks:
      - flask-app-net
  redis:
    image: "redis:alpine"
    networks:
      - flask-app-net
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redis-data:/data
networks:
  flask-app-net:
    driver: bridge
volumes:
  redis-data:
```

### docker-compose.override.yaml (dev-only overrides)
```yaml
web:
  build: .
  environment:
    DEBUG: 'true'
redis:
  ports:
    - 6379:6379
```
Compose applies files in sequence. Later config overrides earlier. Keep a base file for prod and override files per environment ("build once, run anywhere").

### app.py (Flask + Redis last-visited)
```python
import time
import redis
from flask import Flask
from datetime import datetime
app = Flask(__name__)
cache = redis.Redis(host='redis', port=6379)
def get_last_visited():
    try:
        last_visited = cache.getset('last_visited', str(datetime.now().strftime("%Y-%m-%d, %H:%M:%S")))
        if last_visited is None:
            return cache.getset('last_visited', str(datetime.now().strftime("%Y-%m-%d, %H:%M:%S")))
        return last_visited
    except redis.exceptions.ConnectionError as e:
        raise e
@app.route('/')
def index():
    last_visited = str(get_last_visited().decode('utf-8'))
    return 'Hi there! This page was last visited on {}.\n'.format(last_visited)
```
`requirements.txt`: `flask` and `redis`.

## Decision guidance and best practices
- **Storage drivers**: use `overlay2` everywhere possible (file-based, best for read-heavy). Choose `devicemapper` only for write-intensive containers on systems without overlay2 (RHEL/CentOS 7 and older), but it's deprecated. `btrfs`/`zfs` only when the host uses those filesystems. Never use `vfs` in production (slow).
- **Persistence options**: **volumes** (`/var/lib/docker/volumes`, managed by Docker, fastest persistent option, shareable across containers, supports remote/cloud volume drivers for active-active) → default choice. **Bind mounts** when a non-Docker process must also read/write the data, or to share host files like `/etc/resolv.conf`. **tmpfs** (memory only) for sensitive data and non-persistent state.
- **Restart policy**: prefer `unless-stopped` over `always` so you can stop a container manually for maintenance.
- **Logging**: stick to a single default logging driver so logs live in one analysis/visualization place. Don't make Docker logging behave like VM logging: treat each container as its own entity, never tie it to a VM. Don't forward logs directly to the log-analytics solution as the only path (app availability becomes coupled to it). Best pattern: write to local JSON files temporarily, then run a separate log-forwarder container that ships them to your analytics backend (decouples app from external service).
- **Compose**: version-control compose files alongside code (enables GitOps, PRs, gating). Use `.env` files for secrets (kept in a vault like HashiCorp Vault), not committed. Compose works in production effectively when not using a full orchestrator like Kubernetes.
- **Monitoring is continuous**: profile in non-prod to estimate behavior, but real fine-tuning starts in production.

## Pitfalls and gotchas
- Changing the storage driver **wipes existing containers and local images**: plan downtime, re-pull images.
- A foreground `docker run nginx` blocks the terminal because NGINX is a daemon: use `-d`.
- Forgetting `--rm` leaves stopped interactive containers lingering. They only show under `docker ps -a`.
- `devicemapper` with loopback devices is discouraged for production. Use `--storage-opt dm.thinpooldev` for a real block device. It's deprecated and slated for removal.
- Exceeding `--memory` hard limit stops the container (then it follows `--restart`). `--memory-reservation` is only a soft limit.
- In Compose, redeploying a service also redeploys its dependencies by default: use `docker-compose up --no-deps -d <service>` to avoid that.
- Containers get a new IP when recreated and can move between cluster nodes, which confuses traditional monitoring. Use container-aware tools (Prometheus/cAdvisor).
- `:latest` is assumed when no tag is given. Pin versions for reproducibility.

## Command / API cheat-sheet
- `docker --version`: verify install / show engine version.
- `docker run [OPTS] IMAGE[:TAG] [CMD]`: create+start a container.
- `docker run -d`: detached/background (daemon).
- `docker run -it --rm IMAGE /bin/sh`: interactive shell, auto-remove on exit.
- `docker run -p H:C`: map host port H to container port C.
- `docker run --memory / --memory-reservation`: hard / soft memory limits.
- `docker run --restart unless-stopped|always|on_failure|no`: restart policy.
- `docker run --log-driver / --log-opts`: override logging per container.
- `docker ps` / `docker ps -a`: list running / all containers.
- `docker logs <id|name>`: view container stdout/stderr.
- `docker stop|start <name>`: stop / start a container.
- `docker rm -f <name>`: force stop + remove.
- `docker info | grep 'Storage Driver'|'Logging Driver'`: inspect daemon config.
- `docker compose up -d` / `restart <svc>`: declarative bring-up / restart.
- `docker-compose up --no-deps -d <svc>`: redeploy without dependencies.
- `journalctl CONTAINER_NAME=<name>`: read journald-driven container logs.
- `/etc/docker/daemon.json`: daemon config (`storage-driver`, `log-driver`, `log-opts`).

## Where this is covered (topic index)
- Install Docker / apt repo / GPG key → "Install Docker on Ubuntu"
- Non-root docker access / usermod → "Install Docker on Ubuntu" (`usermod -a -G docker`)
- Storage drivers (overlay2, devicemapper, btrfs, zfs, vfs) → "Configure the storage driver", "Decision guidance"
- Volumes / bind mounts / tmpfs / persistence / IOPS → "Core concepts", "Decision guidance" (persistence options)
- Run container / detached / daemon / versioned image → "Run your first container"
- Container debugging / BusyBox / docker logs / docker ps → "Troubleshoot / inspect containers"
- Port mapping / memory limits / restart policy / production NGINX → "Run a production-grade NGINX container"
- Stop/start/remove containers → "Stop / start / remove containers"
- Logging drivers (json-file, journald, syslog, splunk, gelf, fluentd, awslogs, gcplogs, etc.) → "Configure a logging driver", "Logging drivers" list
- Splunk HTTP Event Collector / log-opts → "Configure a logging driver" (Splunk block)
- Monitoring / Prometheus / PromQL / cAdvisor / node exporter / metrics → "Monitor containers with Prometheus..."
- Apache Bench / load test (`ab`) → monitoring workflow step 4
- Host vs container metrics (CPU, memory, disk I/O, network, throttled CPU, swap) → metrics guidance in Prometheus section
- Docker Compose / declarative / GitOps / services/networks/volumes → "Deploy a multi-container app with Docker Compose"
- Compose overrides / multi-environment / .env secrets / --no-deps → "docker-compose.override.yaml", "Decision guidance"
- Registries (Docker Hub, GCR, Nexus, Artifactory) → "Core concepts" (registry options)
