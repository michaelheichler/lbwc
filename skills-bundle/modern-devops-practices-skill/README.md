# modern-devops-practices: Agent Skill

An agent skill distilled from ***Modern DevOps Practices, 2nd Edition*** (Gaurav
Agarwal, Packt Publishing, 2024). It turns the book into a dual-purpose,
agent-actionable reference: an AI agent can **act** (implement the book's
workflows with its exact commands and config templates) and **find** (locate
where a topic is covered and what the book recommends).

## What's inside

- **`SKILL.md`**: the router. Frontmatter (`name`, `description`) drives
  triggering. The body has a **Task → reference** table (act router), a **Topic
  index** (find router), cross-cutting threads, and conventions.
- **`references/`**: one distilled file per chapter (15 chapters + Appendix),
  each with a consistent layout: *When to use · Core concepts · Tools and
  versions · Workflows (how-to) · Reference snippets · Decision guidance and
  best practices · Pitfalls and gotchas · Command / API cheat-sheet · Where this
  is covered.*
- **`modern-devops-practices.skill`**: the packaged artifact (a zip) for
  one-step install.

## Coverage

Docker & container images · Kubernetes (core + advanced resources) · CaaS /
serverless containers (ECS, Fargate, Cloud Run, Knative) · Terraform (IaC) ·
Ansible (config management) · Packer (immutable infra) · CI (GitHub Actions,
Jenkins + Kaniko) · GitOps CD (Argo CD) · CI/CD security & testing (Grype,
External Secrets, binary authorization) · production KPIs / SLOs / SRE · Istio
service mesh (traffic management, mTLS, observability).

## Install

### Claude Code
Copy the skill directory into your skills folder:
```bash
cp -r modern-devops-practices ~/.claude/skills/
```
(Or install the packaged `.skill` via your usual mechanism.)

### Codex CLI
Drop the packaged artifact into the Codex skills directory:
```bash
cp modern-devops-practices.skill ~/.codex/skills/
```

### Other agent runtimes
The skill is plain Markdown. Point your runtime at `SKILL.md` and let it read
`references/*.md` on demand.

## Notes

- The reference files are **transformative distillations** (concepts, commands,
  decision guidance), not the book's text. They preserve the book's exact
  commands and config so the agent reproduces the book's approach faithfully.
- The book standardizes on Ubuntu 22.04 and AWS/GCP/Azure examples and pins
  specific tool versions (recorded per file). Where a topic's API has since
  moved on (e.g. Istio `networking.istio.io/v1alpha3` → `v1`), the files note
  it. Adapt to the user's actual environment.
- Source: *Modern DevOps Practices, 2nd Ed.*, Gaurav Agarwal, Packt 2024
  (ISBN-13 9781803231426). Companion code:
  https://github.com/PacktPublishing/Modern-DevOps-Practices-2e
