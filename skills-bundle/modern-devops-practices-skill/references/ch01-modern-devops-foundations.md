# Chapter 01: The Modern Way of DevOps

> Part 1: Modern DevOps Fundamentals · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need the book's conceptual framing, what "modern DevOps" means versus traditional DevOps, how containers/cloud-native fit in, container architecture (namespaces/cgroups, networking modes), and the book's recommended methodology for migrating workloads from virtual machines to containers. This is a foundations chapter: definitions, decision frameworks, and migration procedure rather than copy-paste tooling config.

## Core concepts
- **DevOps**: A culture + set of practices bridging Dev and Ops via collaboration, shared responsibility, continuous feedback, and automation across the whole SDLC. One combined team builds, deploys, and monitors the software, and specialists remain but cross-skill. Prioritizes **people > processes > tools**.
- **DevOps infinity loop**: DevOps follows a continuous loop, not a linear path. A DevOps team's backlog has two sources: (1) business/architects and (2) customers + production issues.
- **CI (Continuous Integration)**: Frequently merge code from many devs into a shared repo (several times/day). Automated builds + tests give real-time feedback. Detects integration issues early, keeps software releasable.
- **CD (Continuous Delivery)**: Build tested changes into packages, run integration/system tests, then deploy automatically (or on approval) to test/prod. Goal: latest tested artifacts always ready to deploy.
- **IaC (Infrastructure as Code)**: Provision infra (servers, networks, storage) via code + config files, version-controlled in Git, applied through CI/CD. Treats infra as software, often declaratively.
- **CaC (Configuration as Code)**: Manage configuration settings via code + version control, reproducibly. Goes hand in hand with IaC.
- **Monitoring & logging (observability)**: Capture/analyze behavior and performance to find issues (monitoring) and triage them (logging). A major source of the DevOps backlog.
- **Communication & collaboration**: Modern teams use ticketing/Agile tools, wikis, and chat/IM rather than email.
- **Cloud computing**: On-demand delivery of computing resources (servers, storage, DBs, networking, software, analytics) over the internet, pay-as-you-go. CSP owns/manages the underlying infra. Leading CSPs: AWS, Microsoft Azure, Google Cloud Platform.
- **Cloud-native application**: An app built to run natively on the cloud, using cloud services maximally. Inherently scalable, flexible, resilient (fault-tolerant). Characteristics: microservices architecture, containerization, DevOps/automation, dynamic orchestration, use of cloud-native data services.
- **Modern DevOps**: "Automate everything": IaC, CaC, immutable infrastructure, and containers, code for provisioning and configuration. The focus of this book.
- **Matrix of hell**: Running many apps with conflicting dependency versions on one machine becomes unmanageable. Solved historically by VMs and (better) by containers.
- **Container**: An OS process that isolates an app's runtime + dependencies using Linux **namespaces** (isolation) and **cgroups** (CPU/memory/disk I/O limits). No guest OS layer, shares the host kernel. "Build once, run anywhere" / "Package once, deploy anywhere": kills "it works on my machine."
- **Ephemeral/transient workload**: A dispensable container. If one disappears, spin up another with no functional impact. Replace misbehaving ones freely.
- **Stateless vs stateful**: Stateless = no stored state (APIs, functions), easiest to containerize first. Stateful = needs persistent storage (databases), more complex.

## Tools and versions
This chapter is conceptual. It names tools without pinning versions. Tools the book will use later:
- **Docker**: de facto container runtime (alternatives: Rkt, Containerd). All use Linux kernel cgroups (origin: Google, IBM, OpenVZ, SGI, OpenVZ embedded into the Linux kernel).
- **Kubernetes**, **Docker Swarm**: dynamic container orchestrators.
- **Jenkins**, **Argo CD**: CI/CD tools covered later.
- **Git**: source code management, base for the rest of the book.
- **Ansible**: configuration management (CaC).
- **Terraform**: IaC tool.
- **Istio**: service mesh (traffic management, security, observability).
- **DockerHub**: container registry.
- **Hypervisors**: VMware, Oracle VirtualBox (for VMs).
- **CaaS platforms**: AWS ECS & EKS, Google Cloud Run & Kubernetes Engine, Azure ACS & AKS, Oracle OCI & OKE.
- **FaaS platforms** (run containers under the hood): AWS Lambda, Google Functions, Azure Functions, Oracle Functions.

## Workflows (how-to)

### Container build + deploy workflow (the DevOps-native path)
1. Code the app in any language.
2. Write a **Dockerfile** with steps to install dependencies and configure the runtime environment.
3. Use the Dockerfile to create container images:
   a. Build the container image.
   b. Run the container image.
   c. Unit-test the app running in the container.
4. Push the image to a container registry (e.g., DockerHub).
5. Create containers from images and run them in a cluster (e.g., Kubernetes).
6. Embed steps 1-5 in a CI/CD pipeline. Optionally add a **service mesh** (Istio) for blue/green deployments, A/B testing, traffic mirroring, geolocation-based routing.

### Migrating from virtual machines to containers (cyclic process)
The book defines a repeatable, cyclic migration methodology. Revisit phases based on what you learn in production.

1. **Discovery**
   - Understand the application's parts.
   - Assess which legacy parts can be containerized and whether it is technically possible.
   - Define migration scope, agree on goals, benefits, and timelines.
2. **Application requirement assessment**
   - Decide whether to break the app into smaller parts. If so, define the parts and their interactions.
   - Map architecture, performance, and security needs to container-world equivalents.
   - Identify risks and mitigation approaches.
   - Decide migration approach and order. **Always start with the application that has the fewest external dependencies**.
3. **Container infrastructure design** (scalability, networking, storage, security, automation, monitoring)
   - Estimate current and future scale: how many containers? inter-container dependencies? deploy frequency? potential traffic and traffic pattern?
   - Choose infra: on-premises vs cloud, managed Kubernetes vs self-hosted, CaaS for lightweight apps.
   - Plan monitoring/operations: specialist tools? integrate with existing stack?
   - Plan security: regulatory/compliance requirements? does the solution meet them?
4. **Containerizing the application**
   - Create a Dockerfile reproducing the current install steps (hard if no config management like Ansible exists, reverse-engineering the install can take a long time).
   - If splitting into smaller parts, you may need to build from scratch.
   - Define/improve a test suite that also runs against the parallel VM-based app.
5. **Testing**
   - Extensively test to prove parity with the VM app. Run the existing or new test suite.
   - Benchmark the original app. Measure container overhead. Fine-tune to hit performance metrics.
   - Run security testing including penetration testing.
6. **Deployment and rollout**
   - Roll out to production. Learn and loop back to Discovery to refine.
   - Build an automated runbook and CI/CD pipeline to cut cycle time and speed troubleshooting.
   - Use A/B testing with VM and container apps running in parallel before cutting all traffic over.

### Deciding what to containerize (assessment)
1. Classify each workload as **stateless** or **stateful**.
2. Containerize **stateless** workloads first (APIs, functions), no storage dependencies, lowest complexity. More storage dependencies = more complexity.
3. Decide the target infra. If standardizing everything on Kubernetes, avoid a heterogeneous environment. You may then containerize stateful apps too (most web/middleware apps rely on some state).
4. For **databases**: proceed with caution. No industry consensus on containerizing DBs in production. Account for memory, CPU, disk, and every VM dependency, and also weigh team behavior (DBAs may resist the extra container layer).

### Breaking an application into smaller pieces
- Split into **logical, business-aligned components**, not tiny ones. For a shopping site: order, reviews, shopping-cart, catalog containers are OK, create-order / delete-order / update-order containers are overkill.
- Benefits: more frequent releases (change one part without impacting others, faster deploys), independent fine-grained scaling, fault isolation (reviews down ≠ checkout down).
- Don't necessarily split as the first step. A pure lift-and-shift of a monolith yields no benefit and adds container overhead. Re-architect for the container landscape to get ROI.

## Decision guidance and best practices
- **People > processes > tools.** Use tools to automate processes so people hit the right goals.
- **Automate repeatable tasks** so the team focuses on what matters. This improves quality and delivery speed.
- **Start migration with the least-dependency app**, and containerize **stateless before stateful**.
- **Prefer containers over VMs** for portability, density, fast startup, and easy horizontal autoscaling, but VMs remain valid (cloud nodes are VMs, legacy/unmigratable workloads live on VMs).
- **Re-architect, don't just lift-and-shift**, to realize container ROI.
- **Use a container orchestrator** (Kubernetes) in production. Containers rarely run alone. Or use CaaS for lightweight apps.
- **Add a service mesh (Istio)** for advanced traffic management, security, and observability (blue/green, A/B, traffic mirroring, geo-routing).
- **Adopt DevSecOps**: integrate security into the pipeline, automate security testing and vulnerability scanning.
- **Cloud benefits to use**: scalability/auto-scaling, pay-as-you-go cost savings (OpEx over CapEx), flexibility of managed services, reliability (SLAs up to 99.999%), and built-in security.

### Cloud service models
- **IaaS**: VMs, storage, networking, you control OS, apps, config. CSP owns physical infra.
- **PaaS**: platform/runtime/frameworks, focus on code, not infra.
- **SaaS**: pre-built apps via browser/thin client, subscription, on demand.

### Container network types
- **None**: fully isolated (loopback only). Use for testing, staging, or no-network batch jobs.
- **Bridge**: default (Docker uses `docker0`). NATs between container and host, avoids port conflicts, isolates containers on one host. Containers on the same host talk via container IPs. They cannot reach containers on other hosts, **do not use for clustered setups**.
- **Host**: uses host network namespace, bare-metal speed, no NAT, but prone to port conflicts and no isolation, **avoid in most cases** for security/management.
- **Underlay** (MACvlan, IPvlan): exposes host NICs to containers. MACvlan gives each container its own MAC (looks like a physical device). Good for migrating physical-machine apps and strict isolation. Limits: incompatible with switches that block MAC spoofing, NIC MAC ceilings (e.g., Broadcom = 512 MACs/interface).
- **Overlay** (flannel, calico, VXLAN): tunnels between containers on different hosts, appears single-host. Overcomes bridge limits, **use for cluster configuration** with Kubernetes/Docker Swarm.

## Pitfalls and gotchas
- **Containers are not VMs and need no hypervisor**: they are OS processes sharing the host kernel (no guest OS layer).
- **Containers do not inherit OS environment variables**: set them per container.
- **Containers do not inherit `/etc/hosts` entries**: declare them via `docker run`. They *do* inherit the host's DNS settings by default.
- **Proxy config** must be set in the container's env vars or in `~/.docker/config.json`.
- **Bridge network can't span hosts**: use overlay for clusters.
- **Host network has no isolation** and risks port conflicts.
- **Pure lift-and-shift of a monolith** adds container overhead with no benefit.
- **Over-decomposition** into too-tiny microservices creates management overhead.
- **Not every app should be containerized**: heavy GUI apps, legacy monoliths tightly coupled to infra, and apps needing direct hardware access, keep those on VMs.
- **Databases in containers**: no industry consensus. Proceed with caution and account for all resource/dependency needs.

## Command / API cheat-sheet
- `docker exec -it <name> bash`: open a shell session inside a running container.
- `pstree` (inside container): shows only the container's own process tree (namespace isolation), e.g. `nginx---nginx`.
- `hostname -I` (inside container): shows the container's unique IP (Docker daemon acts as DHCP), e.g. `172.17.0.2`.
- `hostname` (inside container): shows the container ID as the default hostname, e.g. `4ee264d964f8` (overridable per network).
- `docker run`: create/run a container, where you declare `/etc/hosts` entries, env vars, DNS flags.
- `Dockerfile`: declarative steps to build a container image.

## Good candidate workloads for containers
Microservices, web applications (frontend/backend APIs/web services), stateful apps (with persistent volumes / statefulsets), batch/scheduled jobs, CI/CD tools (Jenkins, GitLab CI/CD, CircleCI), dev/test environments, IoT apps (edge/gateway), ML and data-analytics apps.

## Where this is covered (topic index)
- DevOps definition, CI, CD, IaC, CaC, observability, collaboration → "Core concepts", "What is DevOps" in source.
- Infinity loop / two backlog sources → "Core concepts".
- Cloud computing, CSPs, benefits, IaaS/PaaS/SaaS → "Decision guidance" (cloud service models) + "Core concepts".
- Cloud-native characteristics (microservices, containerization, orchestration, cloud data services) → "Core concepts".
- Modern vs traditional DevOps, DevSecOps, immutable infrastructure → "Core concepts" + "Decision guidance".
- Why containers / matrix of hell / "it works on my machine" → "Core concepts".
- VMs vs containers, hypervisors → "Pitfalls" + "Core concepts".
- Container architecture, namespaces, cgroups, kernel userspace → "Core concepts" + cheat-sheet.
- Container networking modes (none/bridge/host/underlay/overlay, MACvlan, IPvlan, flannel, calico, VXLAN) → "Container network types".
- Container IP / hostname / DNS / env vars / proxy behavior → "Command / API cheat-sheet" + "Pitfalls".
- Build-and-deploy workflow, Dockerfile, registry/DockerHub, service mesh/Istio → "Container build + deploy workflow".
- Orchestrators (Kubernetes, Docker Swarm), CaaS, FaaS → "Tools and versions" + "Decision guidance".
- VM-to-container migration phases (discovery, assessment, infra design, containerizing, testing, rollout) → "Migrating from virtual machines to containers".
- What to containerize first, stateless vs stateful, databases → "Deciding what to containerize".
- Microservices decomposition (logical vs too-tiny, ROI, lift-and-shift) → "Breaking an application into smaller pieces".
- Good workload candidates for containers → "Good candidate workloads for containers".
