---
name: modern-devops-practices
description: >-
  Authoritative DevOps playbook distilled from "Modern DevOps Practices, 2nd
  Edition" (Gaurav Agarwal, Packt 2024). Use whenever you implement, review,
  design, debug, or explain anything across the modern DevOps toolchain: Docker
  and container images, Kubernetes and advanced Kubernetes resources, CaaS /
  serverless containers (ECS, Fargate, Cloud Run, Knative), Terraform, Ansible,
  Packer, CI with GitHub Actions and Jenkins, GitOps CD with Argo CD, CI/CD
  pipeline security and testing, production KPIs / SLOs / SRE, and Istio service
  mesh (traffic management, mTLS, observability). Trigger even when the user does
  not name the book, e.g. "write a multi-stage Dockerfile", "my pod is
  CrashLoopBackOff", "set up an Argo CD app", "harden my GitHub Actions
  pipeline", "what SLIs should I track", or "split traffic 80/20 with Istio".
  Prefer it over generic knowledge here: it carries the book's exact commands,
  config templates, workflows, and rationale, and maps every topic to a chapter.
---

# Modern DevOps Practices (2nd Edition): Skill

A complete, agent-actionable distillation of *Modern DevOps Practices, 2nd Ed.*
(Gaurav Agarwal, Packt Publishing, 2024). Each chapter has been compressed into
one dense reference file under `references/`. This SKILL.md is the **router**:
it tells you which file to open for a given task or question. The reference
files carry the book's exact commands, config templates, workflows, decision
guidance, and pitfalls.

## How to use this skill

Two modes, they share the same reference files:

1. **Act**: You need to *do* a DevOps task (write a Dockerfile, deploy to
   Kubernetes, author a Terraform module, build a CI/CD pipeline, configure
   Istio, etc.). Find the task in the **Task → reference** table below, open
   that file, and follow its *Workflows* and *Reference snippets* sections.
   They contain the book's exact, copy-pasteable approach.

2. **Find**: You need to know *what the book says* about a topic or *where*
   it's covered. Scan the **Topic index** (or the per-file "Where this is
   covered" sections). Open the matching reference and read its *Core concepts*
   and *Decision guidance* sections, then cite the chapter.

**Operating rules:**
- Treat the reference files as the source of truth for *this book's* approach.
  When a user wants "the modern DevOps way" of doing something, use the book's
  commands and templates rather than improvising, that is the point of this
  skill.
- Don't load all references at once. Open only the file(s) the router points to,
  each is self-contained.
- The book's companion code lives at
  `github.com/PacktPublishing/Modern-DevOps-Practices-2e`. Reference files note
  when a snippet comes from there.
- The book standardizes on Ubuntu 22.04 (Jammy) and (mostly) AWS + GCP for cloud
  examples. Adapt commands to the user's actual OS/cloud, but keep the book's
  structure and intent.

## What the book covers (map)

The book is organized into 5 parts plus an appendix. Reference files live in
`references/`:

**Part 1: Modern DevOps Fundamentals**
- `references/ch01-modern-devops-foundations.md`: what modern DevOps is, containers, the cloud-native shift.
- `references/ch02-git-and-gitops.md`: Git essentials and the GitOps model.
- `references/ch03-docker-containerization.md`: Docker: install, run, storage, logging, Prometheus monitoring, Compose.
- `references/ch04-container-images.md`: building, optimizing, and managing container images.

**Part 2: Container Orchestration and Serverless**
- `references/ch05-kubernetes-orchestration.md`: Kubernetes core: pods, deployments, services.
- `references/ch06-advanced-kubernetes.md`: advanced Kubernetes resources and patterns.
- `references/ch07-caas-and-serverless.md`: Containers as a Service and serverless containers.

**Part 3: Managing Config and Infrastructure**
- `references/ch08-terraform-iac.md`: Infrastructure as Code with Terraform.
- `references/ch09-ansible-config-mgmt.md`: configuration management with Ansible.
- `references/ch10-packer-immutable-infra.md`: immutable infrastructure with Packer.

**Part 4: Delivering Applications with GitOps**
- `references/ch11-ci-github-actions-jenkins.md`: continuous integration (GitHub Actions, Jenkins).
- `references/ch12-cd-argocd.md`: continuous deployment/delivery with Argo CD (GitOps CD).
- `references/ch13-securing-testing-cicd.md`: securing and testing the CI/CD pipeline.

**Part 5: Operating Applications in Production**
- `references/ch14-production-kpis.md`: KPIs/SLIs/SLOs for production services.
- `references/ch15-istio-service-mesh.md`: Istio: traffic management, security (mTLS), observability.

**Appendix**
- `references/appendix-ai-in-devops.md`: the role of AI in DevOps.

## Task → reference (the "act" router)

Match the user's task to a row, then open that file and follow its *Workflows*
and *Reference snippets* sections. Rows are grouped by area.

**Containers & images (Docker)**
| You need to… | Open |
|---|---|
| Decide what to containerize, plan a VM→container migration, pick a container network mode | `ch01-modern-devops-foundations.md` |
| Install/configure Docker. Run, troubleshoot, log, or monitor containers (Prometheus/cAdvisor). Use Docker Compose | `ch03-docker-containerization.md` |
| Write a Dockerfile, build a multi-stage / distroless image, tag & push, add HEALTHCHECK, run a private registry | `ch04-container-images.md` |

**Kubernetes**
| You need to… | Open |
|---|---|
| Stand up Minikube/KinD, write Pod manifests, add liveness/readiness/startup probes, init/sidecar/ambassador/adapter patterns, ConfigMaps & Secrets, debug `ImagePullBackOff`/`CrashLoopBackOff` | `ch05-kubernetes-orchestration.md` |
| Write Deployments with rollout/rollback, Services (ClusterIP/NodePort/LoadBalancer), Ingress routing, HPA autoscaling, StatefulSets + PV/PVC/StorageClass | `ch06-advanced-kubernetes.md` |
| Run containers without managing K8s: ECS/Fargate tasks & services, ALB, CloudWatch. Knative scale-to-zero serverless. Cloud Run. Choose ECS/EKS/AKS/GKE | `ch07-caas-and-serverless.md` |

**Infrastructure & configuration**
| You need to… | Open |
|---|---|
| Provision cloud infra with Terraform: HCL, init/plan/apply, modules, remote state, workspaces, outputs, state surgery, graph | `ch08-terraform-iac.md` |
| Configure servers with Ansible: inventory, playbooks, modules, handlers, variables, Jinja2 templates, roles (LAMP walkthrough) | `ch09-ansible-config-mgmt.md` |
| Bake immutable VM images with Packer (+ Ansible provisioner) and deploy them with Terraform, mutable vs immutable | `ch10-packer-immutable-infra.md` |

**CI/CD & GitOps**
| You need to… | Open |
|---|---|
| Core Git operations, resolve merge conflicts, pull requests, design a GitOps setup (push vs pull, app vs env repos, Gitflow vs GitHub flow) | `ch02-git-and-gitops.md` |
| Build a CI pipeline: GitHub Actions workflow, or scalable Jenkins-on-Kubernetes with Kaniko + JCasC, commit/webhook triggers | `ch11-ci-github-actions-jenkins.md` |
| Pull-based GitOps CD with Argo CD: Application/ApplicationSet, sync/self-heal, Sealed Secrets, dev→prod promotion | `ch12-cd-argocd.md` |
| Secure & test the pipeline: Grype scanning, External Secrets Operator, integration tests in CD, binary authorization (image attestation), PR release gating | `ch13-securing-testing-cicd.md` |

**Production operations**
| You need to… | Open |
|---|---|
| Define SLIs/SLOs/SLAs, error budgets, RTO/RPO, golden signals, SRE practices, decide when to freeze releases | `ch14-production-kpis.md` |
| Operate an Istio service mesh: sidecar injection, ingress Gateway + TLS, mTLS (PeerAuthentication), AuthorizationPolicy, canary (VirtualService weights), traffic mirroring, Kiali/Grafana/Prometheus | `ch15-istio-service-mesh.md` |
| Recommend AI/ML tooling across the DevOps lifecycle (code, test, CI/CD, AIOps) | `appendix-ai-in-devops.md` |

## Topic index (the "find" router)

Keyword → reference file. Each file's own *Where this is covered* section has
the fine-grained pointers, use this for the first hop. (Use Grep across
`references/` for anything not listed.)

| Topic / keyword | Reference |
|---|---|
| modern vs traditional DevOps, DevOps infinity loop, cloud-native, IaaS/PaaS/SaaS, matrix of hell, VM vs container, namespaces/cgroups, microservices decomposition | `ch01-modern-devops-foundations.md` |
| git init/add/commit/branch/rebase, merge conflicts, SSH keys, pull requests, GitOps push vs pull, app vs environment repo, Gitflow vs GitHub flow, configuration drift | `ch02-git-and-gitops.md` |
| docker install, storage drivers (overlay2), volumes/bind mounts, `docker run` flags, logging drivers (journald/splunk), Prometheus + cAdvisor + node exporter, PromQL, Docker Compose, `.env` overrides | `ch03-docker-containerization.md` |
| Dockerfile directives, multi-stage build, distroless, image size optimization, ENTRYPOINT vs CMD, HEALTHCHECK, build/tag/push/prune, image flattening, private registry + TLS/htpasswd, image layers | `ch04-container-images.md` |
| Kubernetes architecture, kubectl, Minikube, KinD, Pod manifest, requests/limits, imagePullPolicy, restartPolicy, liveness/readiness/startup probes, init/sidecar/ambassador/adapter patterns, ConfigMap vs Secret, port-forward, ImagePullBackOff | `ch05-kubernetes-orchestration.md` |
| Deployment, ReplicaSet, rollout/undo, Recreate vs RollingUpdate, maxSurge/maxUnavailable, ClusterIP/NodePort/LoadBalancer, Ingress, nginx ingress controller, HPA/autoscale, StatefulSet, PV/PVC, StorageClass, dynamic provisioning | `ch06-advanced-kubernetes.md` |
| Amazon ECS, AWS Fargate, ecs-cli, task definition, awsvpc, ecsTaskExecutionRole, ALB/NLB, CloudWatch, Knative, scale-to-zero, kn CLI, ksvc, Cloud Run, EKS/AKS/GKE comparison, serverless containers | `ch07-caas-and-serverless.md` |
| Terraform, HCL, azurerm provider, service principal, init/plan/apply/destroy, fmt/validate, tfvars/TF_VAR precedence, modules, remote state backend, state locking, workspaces, outputs, state rm/import, `terraform graph`, taint, lock.hcl | `ch08-terraform-iac.md` |
| Ansible, configuration management, idempotency, agentless SSH, inventory, ansible.cfg, playbooks/plays/tasks/handlers, modules (apt/service/copy/lineinfile/mysql_*), notify, variables, Jinja2 `.j2`, facts, register, roles, become, LAMP stack | `ch09-ansible-config-mgmt.md` |
| immutable vs mutable infrastructure, configuration drift, Packer, `packer init`/`build`, Ansible provisioner, azure-arm builder, managed image versioning, VM scale set, `azurerm_image` data source, blue-green/canary | `ch10-packer-immutable-infra.md` |
| GitHub Actions workflow YAML, actions/checkout, GitHub secrets, commit-SHA image tag, Jenkins controller/agent, scalable Jenkins on K8s, Kaniko, JCasC casc.yaml, Jenkins K8s plugin, JNLP, regcred, Poll SCM vs webhook, CI build performance | `ch11-ci-github-actions-jenkins.md` |
| Argo CD, Application, ApplicationSet, git directory generator, sync/selfHeal, continuous delivery vs deployment, Sealed Secrets, kubeseal, environment repo, Terraform GKE via GitHub Actions, dev→prod promotion | `ch12-cd-argocd.md` |
| container vulnerability scanning, Anchore Grype, GCP Secret Manager, External Secrets Operator, ClusterSecretStore/ExternalSecret, binary authorization, Cloud KMS attestor, sha256 digest vs tag, integration testing in CD, PR release gating, DevSecOps shift-left | `ch13-securing-testing-cicd.md` |
| SLI, SLO, SLA, error budget, four golden signals (latency/errors/traffic/saturation), RTO, RPO, disaster recovery, SRE, toil, 50% ops cap, why-not-100% SLO, chaos engineering, PIR/RCA | `ch14-production-kpis.md` |
| Istio, Envoy sidecar injection, istiod, Gateway/VirtualService/DestinationRule, mTLS, PeerAuthentication STRICT, AuthorizationPolicy, canary traffic weights, traffic mirroring/shadowing, ingress TLS, Kiali, Grafana, Prometheus `istio_requests_total`, subsets v1/v2 | `ch15-istio-service-mesh.md` |
| AI in DevOps, GitHub Copilot, Codex, Tabnine, CodeWhisperer, AI software testing, self-healing tests, AIOps, anomaly detection, predictive maintenance, Harness, Dynatrace, PagerDuty | `appendix-ai-in-devops.md` |

## Cross-cutting threads (topics that span chapters)

The book runs an end-to-end example (a containerized **Blog App**: Flask
microservices + MongoDB) through the GitOps chapters. When a task touches
several stages, read the chapters in pipeline order:

- **GitOps end-to-end:** `ch02` (model) → `ch11` (CI) → `ch12` (Argo CD CD) → `ch13` (secure/test) → `ch15` (mesh).
- **Provisioning a cluster + infra:** `ch08` (Terraform) → `ch12`/`ch13` (Terraform-driven GKE + add-ons).
- **Secrets, three ways:** Sealed Secrets (`ch12`) vs External Secrets Operator + cloud Secret Manager (`ch13`) vs TLS secret for Istio gateway (`ch15`). `ch13` explains why ESO supersedes Sealed Secrets.
- **Canary / blue-green:** conceptual intro (`ch01`), Deployment-level (`ch06`), mesh-level traffic weights (`ch15`).
- **Observability/monitoring:** Docker+Prometheus (`ch03`), KPIs/golden signals (`ch14`), Istio + Kiali/Grafana (`ch15`).
- **Immutable infra path:** Packer images (`ch10`) vs containers (`ch03`/`ch04`), both contrast with mutable Ansible config (`ch09`).

## Conventions in the reference files

Every reference file follows the same layout, so you can jump straight to what
you need:
*When to use this file · Core concepts · Tools and versions · Workflows (how-to)
· Reference snippets · Decision guidance and best practices · Pitfalls and
gotchas · Command / API cheat-sheet · Where this is covered (topic index).*

For **acting**, jump to *Workflows* and *Reference snippets*. For **explaining
or deciding**, read *Core concepts* and *Decision guidance*. For **locating** a
detail, scan *Where this is covered*. The book's exact versions are recorded in
*Tools and versions*, flag to the user when their environment differs.
