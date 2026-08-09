# Chapter 04: Creating and Managing Container Images

> Part 1: Modern DevOps Fundamentals · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when writing a Dockerfile, building/tagging/pushing images, shrinking image size (multi-stage, distroless, flattening), or standing up a private Docker registry, following this book's exact directives, commands, and best practices. Exercise files live under `ch4/` in the repo: https://github.com/PacktPublishing/Modern-DevOps-Practices-2e

## Core concepts
- **Image vs container**: An image is the immutable blueprint (packages, source, deps, libs + steps to run them). A container is a running instance of an image. "Build once, run anywhere."
- **Layered filesystem**: Each Dockerfile directive creates an intermediate read-only layer that is a *delta* of the previous filesystem. Layers are shared across images/containers (less disk + network, only deltas transmitted). Directives like `CMD`/`EXPOSE`/`ENV` add 0 B. `RUN apt install`/`ADD` consume space.
- **Writable layer**: Each running container gets a unique writable layer on top of the read-only image layers. `CMD`/`ENTRYPOINT` runtime changes only touch this layer.
- **Build cache**: Docker builds from the first changed line to the end and pulls earlier unchanged layers from cache. Put rarely-changing layers (packages/deps) first, frequently-changing layers (source code) last for fast CI/CD.
- **Directive**: A single instruction (step) in a Dockerfile.
- **Single-stage build**: One `FROM`. Build toolchain ends up in the final image (bloated, e.g. 803 MB Go image).
- **Multi-stage build**: Multiple `FROM` stages. Build in stage 1, copy only the artifact into a lean runtime stage (e.g. 9.17 MB), about 100x smaller.
- **Distroless image**: Minimal image with only the app + deps + runtime files, no package manager, no shell → smallest attack surface (e.g. 22.3 MB). Optimizes performance, security, and cost.
- **Registry vs repository**: A registry (e.g. Docker Hub, default `docker.io`) is a stateless, scalable, Apache-licensed store/distribution server. It holds many repositories, and a repository holds many versions/tags of one image.

## Tools and versions
- **Docker** on Ubuntu 18.04 Bionic LTS or later, with `sudo`. BuildKit build output (`[+] Building ... FINISHED`).
- **Docker Hub** account required (https://hub.docker.com/).
- Base images used in the chapter: `ubuntu:bionic`, `golang:1.20.5`, `alpine:3.18.0`, `gcr.io/distroless/base`, `nginx`, `registry:2` / `registry:2.7.0`.
- **Distroless** images: Google, `gcr.io/distroless/*`, https://github.com/GoogleContainerTools/distroless

## Workflows (how-to)

### Write a basic Dockerfile (NGINX example)
```dockerfile
FROM ubuntu:bionic
RUN apt update && apt install -y curl
RUN apt update && apt install -y nginx
CMD ["nginx", "-g", "daemon off;"]
```
- `FROM` sets the base image. `RUN` executes build-time commands (chain related commands with `&&` to keep one layer). Repeat `apt update` before each install so layers have no implicit dependency on a cached prior layer (else `nginx` install can fail). `CMD` is the default runtime command. For long-running processes the final `CMD` must not return control to the shell (`nginx -g daemon off;` runs in foreground).

### Build, run, and verify
```bash
docker build -t <your_dockerhub_user>/nginx-hello-world .
docker run -d -p 80:80 <your_dockerhub_user>/nginx-hello-world
docker ps
curl localhost
```
- Image name structure: `<registry-url>/<account-name>/<container-image-name>:<version>` (registry defaults to `docker.io`).
- General build form: `docker build -t <image-name>:version <build_context>`.

### Add custom content + reliability directives
```dockerfile
FROM ubuntu:bionic
RUN apt update && apt install -y curl
RUN apt update && apt install -y nginx
WORKDIR /var/www/html/
ADD index.html ./
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=60s --timeout=10s --start-period=20s --retries=3 CMD curl -f localhost
```
- `WORKDIR`: sets the working dir (last one is where you land on `exec`), absolute or relative.
- `ADD`: copies a local file into the image, can also fetch URLs and auto-extract TAR/ZIP. Use `COPY` for plain file copies.
- `EXPOSE`: documents the port (clarity, doesn't publish, `-p` does).
- `STOPSIGNAL`: signal sent on `docker stop`.
- `HEALTHCHECK`: runs a `CMD` probe. Container reports `healthy`/`unhealthy`/`health: starting`. Fields: `--interval` (default 30s), `--timeout` (default 30s), `--start-period` (default 0s), `--retries` (default 3). It only *reports*, you must act on unhealthy containers (cron/systemd script). Do NOT bake into images run on Kubernetes (use liveness/readiness probes) or Docker Compose (define healthcheck in YAML).

### Inspect image layers / history
```bash
docker history <image>
```

### Single-stage build (Go): produces a bloated image (~803 MB)
```dockerfile
FROM golang:1.20.5
WORKDIR /tmp
COPY app.go .
RUN GO111MODULE=off GOOS=linux go build -a -installsuffix cgo -o app . && chmod +x ./app
CMD ["./app"]
```

### Multi-stage build (Go): lean image (~9.17 MB)
```dockerfile
FROM golang:1.20.5 AS build
WORKDIR /tmp
COPY app.go .
RUN GO111MODULE=off GOOS=linux go build -a -installsuffix cgo -o app . && chmod +x ./app
FROM alpine:3.18.0
WORKDIR /tmp
COPY --from=build /tmp/app .
CMD ["./app"]
```
- First `FROM ... AS build` names the stage. `COPY --from=build /tmp/app .` pulls only the compiled binary into a lean runtime base. No `AS` on the final stage (that's the image you ship).

### Distroless build (Go): most secure (~22.3 MB, no shell)
```dockerfile
FROM golang:1.20.5 AS build
WORKDIR /tmp
COPY app.go .
RUN GO111MODULE=off GOOS=linux go build -a -installsuffix cgo -o app . && chmod +x ./app
FROM gcr.io/distroless/base
WORKDIR /tmp
COPY --from=build /tmp/app .
CMD ["./app"]
```
- `gcr.io/distroless/base` is a minimal glibc system with no package manager/shell. Good for Go/Rust/D binaries. Distroless variants exist for Python/Java.

### Tag, login, push images
```bash
docker login
docker push <your_dockerhub_user>/nginx-hello-world:latest
docker push -a <your_dockerhub_user>/go-hello-world        # push all tags (--all-tags)
```
- Layers already on the registry are `Mounted from ...` rather than re-uploaded.

### Pull and remove images
```bash
docker pull nginx                  # explicit pull (run pulls only if absent)
docker rmi nginx                   # fails if a running container uses it
docker rmi -f nginx                # force: stops+removes container then image (dangerous)
docker images prune                # prune dangling layers from failed/old builds
```

### Flatten an image (last resort)
```bash
docker run -d --name nginx <your_dockerhub_user>/nginx-hello-world:latest
docker export nginx > nginx-hello-world-flat.tar
cat nginx-hello-world-flat.tar | docker import - <your_dockerhub_user>/nginx-hello-world:flat
docker history <your_dockerhub_user>/nginx-hello-world:flat   # single layer
```
- Result is one layer. Only do this if you measure a real performance gain, it loses layer sharing and adds filesystem overhead.

### Run a basic private registry
```bash
docker run -d -p 80:5000 --restart=always --name registry registry:2
docker tag <your_dockerhub_user>/nginx-hello-world:latest \
  localhost/<your_dockerhub_user>/nginx-hello-world:latest
docker push localhost/<your_dockerhub_user>/nginx-hello-world:latest
```
- Tag structure for routing: `<registry_url>/<user>/<image_name>:<image_version>`.

### Run a secured private registry (TLS + htpasswd auth + volume)
```bash
sudo mkdir -p /mnt/registry/certs
sudo mkdir -p /mnt/registry/auth
sudo chmod -R 777 /mnt/registry

# generate htpasswd (user/pass) via the registry image's htpasswd entrypoint
docker run --entrypoint htpasswd registry:2.7.0 -Bbn user pass > /mnt/registry/auth/htpasswd

# self-signed TLS cert (use server name/IP as the FQDN)
openssl req -newkey rsa:4096 -nodes -sha256 \
  -keyout /mnt/registry/certs/domain.key -x509 -days 365 -out /mnt/registry/certs/domain.crt

docker rm -f registry

docker run -d -p 443:443 --restart=always --name registry \
  -v /mnt/registry/certs:/certs \
  -v /mnt/registry/auth:/auth \
  -v /mnt/registry/registry:/var/lib/registry \
  -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  -e REGISTRY_AUTH=htpasswd \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  registry:2

docker login https://localhost          # username: user, password: pass
docker push localhost/<your_dockerhub_user>/nginx-hello-world
```
- Mount `/var/lib/registry` to a volume or you lose all images on restart.

## Reference snippets

### ENTRYPOINT vs CMD
- Default `ENTRYPOINT` is `/bin/sh -c`. `CMD` args are appended to it (so `CMD ["nginx","-g","daemon off;"]` runs as `/bin/sh -c nginx -g daemon off;`).
- A custom `ENTRYPOINT ["nginx","-g"]` lets `docker run nginx daemon off;` append its args. Self-contained form: `ENTRYPOINT ["nginx", "-g", "daemon off;"]`.
- Multiple `CMD` directives → only the last is used. Multiple `RUN` directives → all execute (each builds a layer).

## Decision guidance and best practices
- **Order layers by change frequency**: packages/deps first, source code last → maximizes cache hits, faster CI/CD.
- **Minimize layers**: combine commands with `&&` in one `RUN`, avoid consecutive `RUN`s.
- **Ship only what's needed**: no Go toolkit / heavy package managers at runtime → use multi-stage builds, prefer Alpine, prefer distroless for security.
- **Use `ENTRYPOINT` over `CMD`** when you want to lock default behavior (more secure, users can't override it).
- **Always `EXPOSE`** ports for clarity, always set `STOPSIGNAL` when stop behavior matters.
- **Tag with semantic versions, never rely on `latest`**: (1) orchestrators assume `latest` is already present and skip pulling (wasted bandwidth, Docker Hub rate-limits pulls), and (2) versioned tags enable fast rollback and stable, reproducible production deployments.
- **Prune regularly** to reclaim space from dangling/old layers.
- **Flatten only as a last resort**, after confirming a real performance win.
- **Don't bake `HEALTHCHECK` for Kubernetes/Compose**: use liveness/readiness probes or Compose YAML healthchecks.
- General container hygiene: official base images, one service per container, env vars for config/secrets (not hardcoded), persistent data in volumes/bind mounts, meaningful container names, CPU/memory limits, restart policies, network isolation, logs to stdout/stderr, run as non-root, version-control Dockerfiles, regular cleanup/prune.

## Pitfalls and gotchas
- Omitting `apt update` before a later `apt install` can fail because Docker reuses the cached package index from an earlier layer.
- `docker rmi <image>` errors if a running container references it. `docker rmi -f` stops+removes the container too (destructive, avoid unless intentional).
- `docker run` does NOT re-pull an image already present locally. Use `docker pull` to refresh, but `latest` drifts, so you may silently get a different version.
- Single-stage builds bloat images with the entire build toolchain (803 MB Go example).
- Basic private registry without a volume loses all images on container restart. Without TLS/auth it is open to anyone.
- Distroless images have no shell: you cannot `docker exec` a shell into them to debug (that's the point, the trade-off is harder troubleshooting).

## Command / API cheat-sheet
- `docker build -t <name>:<tag> <context>`: build an image from a Dockerfile.
- `docker run -d -p <host>:<cont> <image>`: run a container detached with port mapping.
- `docker ps`: list running containers (shows health status).
- `docker history <image>`: show image layers, sizes, and creating commands.
- `docker images`: list images and sizes.
- `docker pull <image>`: explicitly download an image.
- `docker rmi [-f] <image>`: remove an image (`-f` forces, removing the container too).
- `docker images prune`: remove dangling image layers.
- `docker login [registry]` / `docker push [-a] <image>`: authenticate / push (all tags with `-a`).
- `docker tag <src> <dst>`: add another name/registry route to an image.
- `docker export <container> > x.tar` / `docker import - <image>`: flatten via export/import.
- Dockerfile directives: `FROM`, `RUN`, `CMD`, `ENTRYPOINT`, `WORKDIR`, `ADD`, `COPY`, `COPY --from=<stage>`, `EXPOSE`, `STOPSIGNAL`, `HEALTHCHECK`, `FROM ... AS <stage>`.

## Where this is covered (topic index)
- Docker architecture (daemon, client, registry) → Core concepts, "Docker architecture" section.
- Layers / layered filesystem / image history / deltas → Core concepts, "Inspect image layers".
- Writing a Dockerfile, FROM/RUN/CMD, apt update gotcha → "Write a basic Dockerfile".
- WORKDIR, ADD vs COPY, EXPOSE, STOPSIGNAL, HEALTHCHECK → "Add custom content + reliability directives".
- ENTRYPOINT vs CMD, RUN vs CMD → "Reference snippets".
- Build / run / verify / image naming structure → "Build, run, and verify".
- Single-stage vs multi-stage builds, image size optimization → "Single-stage build", "Multi-stage build".
- Distroless / minimal / secure / no-shell images, performance/security/cost → "Distroless build", Core concepts.
- Tagging, semantic versioning, latest tag pitfalls → "Tag, login, push", Decision guidance.
- Pull / rmi / prune / dangling images → "Pull and remove images".
- Push to Docker Hub, --all-tags, mounted layers → "Tag, login, push".
- Flattening images (export/import) → "Flatten an image".
- Private registry (basic + TLS/htpasswd/volume) → "Run a basic/secured private registry".
- Cloud registries (ECR, GCR, ACR, OCI, Quay) and Nexus/Artifactory → see "Other public registries" in source, managed/private options.
- Build cache, CI/CD speed, layer ordering best practice → Core concepts, Decision guidance.
