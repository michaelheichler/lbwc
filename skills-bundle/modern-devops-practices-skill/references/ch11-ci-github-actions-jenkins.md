# Chapter 11: Continuous Integration with GitHub Actions and Jenkins

> Part 4: Delivering Applications with GitOps · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to build a CI pipeline for a containerized app, either with GitHub Actions (SaaS, zero-setup) or with a scalable, self-hosted Jenkins-on-Kubernetes setup using Kaniko for daemonless image builds. Also covers post-commit/webhook triggers and CI build-performance tuning.

## Core concepts
- **CI (Continuous Integration)**: developers commit to source control frequently (several times/day). Automated tooling detects the commit and builds + tests it, giving an immediate feedback loop. Goal: catch breakage as soon as code is checked in, when bugs are cheapest to fix.
- **GitOps in CI**: the build/test config (workflow YAML, build scripts) lives in the same repo as the application code, so Git is the single source of truth. The book tags images with the Git commit SHA to bind each image to its commit.
- **Docker is inherently CI-compliant**: you can run unit tests inside the `Dockerfile` (`RUN python app.test.py`). A failing test fails the build, so the Dockerfile alone can build + test.
- **GitHub Actions**: SaaS CI/CD bundled with every GitHub repo. Workflows are YAML in `.github/workflows/`. Best for getting started fast.
- **Jenkins**: most popular open-source CI tool (Java, plugin-based, controller-agent model). Runs anywhere but has management overhead.
- **Controller-agent model**: the Jenkins controller stores config/management data. Builds are offloaded to agents. Static agents don't scale well. Modern approach spins up an agent on demand per build.
- **Scalable Jenkins on Kubernetes**: Jenkins controller tells Kubernetes to create a fresh agent **pod** per build, which connects back to the controller via JNLP (port 50000) and runs the build. This is build-on-demand.
- **Kaniko**: Google tool that builds container images inside a cluster **without** the Docker daemon and **without** privileged mode, the secure way to build images in Kubernetes (privileged mode would expose the host filesystem).
- **Post-commit trigger / webhook**: GitHub fires a webhook to the CI server on commit, so builds start automatically. Preferred over Jenkins SCM polling (polling is resource-intensive at scale).

## Tools and versions
- **GitHub Actions**: SaaS CI/CD, `actions/checkout@v2` used for checkout.
- **Jenkins**: base image `jenkins/jenkins`, agent base `jenkins/inbound-agent`, configured via **Jenkins Configuration as Code (JCasC)**.
- **Kaniko**: `gcr.io/kaniko-project/executor:v1.13.0`, daemonless image builder.
- **Kubernetes / GKE**: Google Kubernetes Engine, `gcloud` CLI. Jenkins Kubernetes plugin spins up agent pods.
- **Docker**: `python:3.7-alpine` base for the sample app, Docker Hub as registry.
- **Blog App**: sample microservices app, Python **Flask** + **MongoDB**. Microservices: User, Posts, Reviews, Ratings (internal, called by Reviews), Frontend (Bootstrap UI). Each service has `app.py`, `app.test.py`, `requirements.txt`, `Dockerfile`. Repo: github.com/PacktPublishing/Modern-DevOps-Practices-2e (`ch11/`, `blog-app/`).

## Workflows (how-to)

### Build + test a microservice with Docker (CI inside the Dockerfile)
The `posts` service Dockerfile runs the unit test as a build step. A failed test fails the build.
```dockerfile
FROM python:3.7-alpine
ENV FLASK_APP=app.py
ENV FLASK_RUN_HOST=0.0.0.0
RUN apk add --no-cache gcc musl-dev linux-headers
COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt
EXPOSE 5000
COPY . .
RUN python app.test.py
CMD ["flask", "run"]
```
Build with plain (stepwise) progress so you see each test step:
```bash
docker build --progress=plain -t posts .
# ...
# #10 [6/6] RUN python app.test.py
# #10 0.676 Ran 8 tests in 0.026s   -> OK
```

### Set up CI with GitHub Actions
1. Create a GitHub repo (book uses `mdo-posts`) and clone it:
   ```bash
   git clone https://github.com/<GitHub_Username>/mdo-posts.git
   cd mdo-posts
   cp ~/modern-devops/blog-app/posts/* .   # app.py, app.test.py, requirements.txt, Dockerfile
   ```
2. Create the workflow directory and add `build.yaml` (see Reference snippets):
   ```bash
   mkdir -p .github/workflows
   mv build.yml .github/workflows/
   ```
3. Add repo secrets at `https://github.com/<your_user>/mdo-posts/settings/secrets/actions`:
   ```
   DOCKER_USER=<Docker Hub username>
   DOCKER_PASSWORD=<Docker Hub password>
   ```
4. Commit and push to trigger the build:
   ```bash
   git add --all
   git commit -m 'Initial commit'
   git push
   ```
5. View runs at `https://github.com/<your_user>/mdo-posts/actions`. On success the image lands in Docker Hub, tagged with the short Git SHA. A failing unit test (e.g. returning `pos` instead of `post`) fails the **Build the Docker image** step with an `AssertionError`.

### Set up scalable Jenkins on Kubernetes with Kaniko
1. **Provision GKE** (Google Cloud Shell):
   ```bash
   gcloud services enable container.googleapis.com
   gcloud container clusters create cluster-1 --num-nodes 2 \
     --enable-autoscaling --min-nodes 1 --max-nodes 5 --zone us-central1-a
   ```
   Clone resources: `cd modern-devops/ch11/jenkins/jenkins-controller`.
2. **Write `casc.yaml`** (JCasC): Global Security, no executors on controller, and the Kubernetes cloud + agent pod template (see Reference snippets). Replace placeholders:
   ```bash
   kubectl cluster-info | grep "control plane"   # get control plane IP
   sed -i 's/<kubernetes_control_plane_ip>/actual_ip/g' casc.yaml
   sed -i 's/<your_dockerhub_user>/actual_dockerhub_user/g' casc.yaml
   ```
3. **Build + push the Jenkins controller image** (bakes in casc.yaml + plugins):
   ```bash
   docker build -t <your_dockerhub_user>/jenkins-controller-kaniko .
   docker login
   docker push <your_dockerhub_user>/jenkins-controller-kaniko
   ```
4. **Build + push the Jenkins agent image** (JNLP agent + Kaniko binary):
   ```bash
   cd ~/modern-devops/ch11/jenkins/jenkins-agent
   docker build -t <your_dockerhub_user>/jenkins-jnlp-kaniko .
   docker push <your_dockerhub_user>/jenkins-jnlp-kaniko
   ```
5. **Deploy to Kubernetes** (from `jenkins-controller/`):
   ```bash
   kubectl apply -f jenkins-sa-crb.yaml          # jenkins ServiceAccount + ClusterRoleBinding (cluster-admin)
   kubectl apply -f jenkins-pvc.yaml             # PersistentVolumeClaim for /var/jenkins_home
   kubectl create secret docker-registry regcred \
     --docker-username=<username> --docker-password=<password> \
     --docker-server=https://index.docker.io/v1/
   sed -i 's/<your_dockerhub_user>/actual_dockerhub_user/g' jenkins-deployment.yaml
   kubectl apply -f jenkins-deployment.yaml      # controller pod; ports 8080 (UI) + 50000 (JNLP); initContainer chowns jenkins_home
   kubectl apply -f jenkins-svc.yaml             # LoadBalancer Service exposing 8080 + 50000
   kubectl get svc jenkins-service               # grab EXTERNAL-IP
   ```
6. Access Jenkins at `http://<LOAD_BALANCER_EXTERNAL_IP>:8080` and log in with the admin id/password (from `JENKINS_ADMIN_ID` / `JENKINS_ADMIN_PASSWORD`).

### Create and run a Jenkins job (Kaniko build)
1. Copy the Kaniko build script into the repo, commit, and push:
   ```bash
   cp ~/modern-devops/ch11/jenkins/jenkins-agent/build.sh ~/mdo-posts/
   ```
2. In Jenkins: **New Item** -> **Freestyle Job** -> name it (match the repo name).
3. **Source Code Management** -> **Git** -> add repo URL + branch.
4. **Build Triggers** -> **Poll SCM** (initial approach, polls every minute).
5. **Build** -> **Add Build Step** -> **Execute shell**, run `build.sh` with args `<your_dockerhub_user>/<image>` and the image tag. **Save**.
6. **Build Now** (or push a change). Jenkins creates an agent pod, runs the unit test, builds with Kaniko, and pushes to Docker Hub. Check **Build** -> **Console Output**.

### Switch Jenkins from polling to a GitHub webhook trigger
1. Jenkins: **Job configuration** -> **Build Triggers** -> enable **GitHub hook trigger for GITScm polling**. **Save**.
2. GitHub: repo **Settings** -> **Webhooks** -> **Add Webhook**, point the payload URL at the Jenkins server. **Add Webhook**.
3. Push a change: the Jenkins job builds automatically (no controller polling).

## Reference snippets

### GitHub Actions workflow (`.github/workflows/build.yaml`)
```yaml
name: Build and Test App
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Login to Docker Hub
      id: login
      run: docker login -u ${{ secrets.DOCKER_USER }} -p ${{ secrets.DOCKER_PASSWORD }}
    - name: Build the Docker image
      id: build
      run: docker build . --file Dockerfile --tag ${{ secrets.DOCKER_USER }}/mdo-posts:$(git rev-parse --short "$GITHUB_SHA")
    - name: Push the Docker image
      id: push
      run: docker push ${{ secrets.DOCKER_USER }}/mdo-posts:$(git rev-parse --short "$GITHUB_SHA")
```

### JCasC `casc.yaml` (security + Kubernetes cloud + agent template)
```yaml
jenkins:
  systemMessage: "Welcome to Jenkins!"
  numExecutors: 0
  remotingSecurity:
    enabled: true
  securityRealm:
    local:
      allowsSignup: false
      users:
       - id: ${JENKINS_ADMIN_ID}
         password: ${JENKINS_ADMIN_PASSWORD}
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:admin"
        - "Overall/Read:authenticated"
  clouds:
  - kubernetes:
      serverUrl: "https://<kubernetes_control_plane_ip>"
      jenkinsUrl: "http://jenkins-service:8080"
      jenkinsTunnel: "jenkins-service:50000"
      skipTlsVerify: false
      useJenkinsProxy: false
      maxRequestsPerHost: 32
      name: "kubernetes"
      readTimeout: 15
      podLabels:
        - key: jenkins
          value: agent
      templates:
      - name: "jenkins-agent"
        label: "jenkins-agent"
        hostNetwork: false
        nodeUsageMode: "NORMAL"
        serviceAccount: "jenkins"
        imagePullSecrets:
          - name: regcred
        yamlMergeStrategy: "override"
        containers:
        - name: jnlp
          image: "<your_dockerhub_user>/jenkins-jnlp-kaniko"
          workingDir: "/home/jenkins/agent"
          command: ""
          args: ""
          livenessProbe:
            failureThreshold: 1
            initialDelaySeconds: 2
            periodSeconds: 3
            successThreshold: 4
            timeoutSeconds: 5
        volumes:
          - secretVolume:
              mountPath: /kaniko/.docker
              secretName: regcred
```

### Jenkins controller Dockerfile
```dockerfile
FROM jenkins/jenkins
ENV CASC_JENKINS_CONFIG /usr/local/casc.yaml
ENV JAVA_OPTS -Djenkins.install.runSetupWizard=false
COPY casc.yaml /usr/local/casc.yaml
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
```

### Jenkins agent Dockerfile (multi-stage: JNLP agent + Kaniko binary)
```dockerfile
FROM gcr.io/kaniko-project/executor:v1.13.0 as kaniko
FROM jenkins/inbound-agent
COPY --from=kaniko /kaniko /kaniko
WORKDIR /kaniko
USER root
```

### Kaniko build script (`build.sh`): daemonless build + push
```bash
IMAGE_ID=$1 && \
IMAGE_TAG=$2 && \
export DOCKER_CONFIG=/kaniko/.dockerconfig && \
/kaniko/executor \
  --context $(pwd) \
  --dockerfile $(pwd)/Dockerfile \
  --destination $IMAGE_ID:$IMAGE_TAG \
  --force
```

## Decision guidance and best practices
- **GitHub Actions vs Jenkins**: use GitHub Actions if you're on GitHub and want fast, low-overhead CI. Use Jenkins when you need to run CI anywhere / self-host, at the cost of more management overhead. Cloud-native alternatives: AWS CodeCommit + CodeBuild / CodePipeline, Azure DevOps, GCP Cloud Build, Travis CI.
- **Tag images with the Git commit SHA** to bind builds to commits (Git as single source of truth).
- **Always pin action versions** (e.g. `@v2`) so a later incompatible release doesn't break your pipeline.
- **Store secrets in GitHub secrets** (or Kubernetes Secrets), never in the repo with code.
- **Prefer post-commit webhooks over SCM polling**: polling hundreds of jobs every minute is resource-intensive. Webhooks decouple developers from CI management.
- **Use Kaniko, not privileged Docker-in-Docker**, for in-cluster builds (security, no Docker daemon needed).
- **Build-performance best practices**: aim for fast builds (small/shared base images, fast tests, offload long-running tests to a separate job/pipeline), parallelize builds and tests, use caching (Docker layer cache, package-manager caches), incremental builds (rebuild only what changed), optimize tests (run fast unit tests before slow integration/e2e, use JUnit/TestNG/PyTest to categorize+parallelize), configure build reporting (email/Slack so devs don't log into the CI tool), right-size build machines to the workload (CPU- vs memory-heavy), keep images/dependencies minimal (use multi-stage builds to avoid bloat and reduce attack surface), use artifact repos (Artifactory/Nexus) with versioning + retention, use IaC + containers for consistent build environments, adopt cloud CI/CD for elastic parallelization, monitor/profile pipelines for bottlenecks, automate cleanup of stale artifacts/containers/VMs, and document standards and train the team.

## Pitfalls and gotchas
- Running Jenkins agents in **privileged mode** to do Docker builds exposes the host filesystem, a serious security hole. Admins typically disable it. Use Kaniko instead.
- Vanilla Jenkins is **insecure by default**: anyone can do anything. You must configure Global Security (`securityRealm`, `authorizationStrategy`, `remotingSecurity`) before exposing it.
- Set `numExecutors: 0` on the controller so builds never run on it (they belong on agents).
- A failed unit test inside the Dockerfile (`RUN python app.test.py`) fails the whole image build (that's intentional, but means a broken test blocks the push).
- SCM polling every minute does not scale. Switch to webhooks once you have many jobs.
- Persist Jenkins data with a PVC mounted at `/var/jenkins_home`, or you lose config/state when the pod is recreated.
- The agent JNLP port is 50000: expose it on the Service and set `jenkinsTunnel` to `jenkins-service:50000` or agents can't connect.

## Command / API cheat-sheet
- `docker build --progress=plain -t posts .`: build with stepwise log output (see each test step).
- `git rev-parse --short "$GITHUB_SHA"`: short commit SHA used as the image tag.
- `gcloud services enable container.googleapis.com`: enable the GKE API.
- `gcloud container clusters create cluster-1 --num-nodes 2 --enable-autoscaling --min-nodes 1 --max-nodes 5 --zone us-central1-a`: autoscaling GKE cluster.
- `kubectl cluster-info | grep "control plane"`: get the control plane IP for `serverUrl`.
- `kubectl create secret docker-registry regcred --docker-username=<u> --docker-password=<p> --docker-server=https://index.docker.io/v1/`: registry credential secret for Kaniko/image pulls.
- `kubectl apply -f jenkins-{sa-crb,pvc,deployment,svc}.yaml`: deploy Jenkins stack.
- `kubectl get svc jenkins-service`: find the LoadBalancer external IP.
- `jenkins-plugin-cli --plugin-file plugins.txt`: install plugins into the controller image.
- `/kaniko/executor --context . --dockerfile ./Dockerfile --destination IMAGE:TAG --force`: daemonless build + push.
- GitHub Actions YAML keys: `on` (push/pull_request triggers), `jobs.<job>.runs-on`, `jobs.<job>.steps[].uses/name/id/run`, `${{ secrets.X }}`.

## Where this is covered (topic index)
- **What is CI / feedback loop / why automate** -> Core concepts, "The importance of automation".
- **Sample app / Blog App / microservices / Flask / MongoDB** -> Tools and versions (Blog App).
- **GitHub Actions setup / workflow YAML / `.github/workflows`** -> Workflows: "Set up CI with GitHub Actions", Reference: `build.yaml`.
- **GitHub secrets / DOCKER_USER / DOCKER_PASSWORD** -> "Set up CI with GitHub Actions" step 3, best practices.
- **Image tagging with commit SHA / GitOps** -> Core concepts, best practices.
- **Run tests in a Dockerfile / `RUN python app.test.py`** -> Workflows: "Build + test a microservice", pitfalls.
- **Jenkins / controller-agent model / scalable Jenkins** -> Core concepts, "Set up scalable Jenkins".
- **Kaniko / daemonless build / privileged-mode security** -> Core concepts, pitfalls, agent Dockerfile, `build.sh`.
- **JCasC / Jenkins Configuration as Code / casc.yaml / Global Security** -> Reference: `casc.yaml`, "Set up scalable Jenkins" step 2.
- **Kubernetes plugin / agent pods / JNLP / pod template** -> `casc.yaml` clouds section, pitfalls.
- **GKE / cluster creation / autoscaling** -> Workflows step 1, cheat-sheet.
- **Jenkins deployment manifests (SA, ClusterRoleBinding, PVC, Secret regcred, Deployment, LoadBalancer Service)** -> "Set up scalable Jenkins" step 5.
- **Freestyle job / Execute shell / Source Code Management / Poll SCM** -> "Create and run a Jenkins job".
- **Post-commit triggers / GitHub webhooks / Jenkins hook trigger** -> "Switch Jenkins from polling to a GitHub webhook trigger", best practices.
- **Build performance / caching / parallelization / multi-stage / artifact repos** -> Decision guidance and best practices.
- **Cloud CI alternatives (CodeBuild, Azure DevOps, Cloud Build, Travis)** -> Decision guidance.
