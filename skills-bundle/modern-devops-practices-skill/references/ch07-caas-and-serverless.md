# Chapter 07: Containers as a Service (CaaS) and Serverless Computing for Containers

> Part 2: Container Orchestration and Serverless · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to run containers without managing a full Kubernetes control plane: deploying tasks/services on Amazon ECS (EC2 or Fargate launch types), choosing between cloud CaaS offerings (ECS/EKS/AKS/GKE/Cloud Run), or installing and using Knative for open-source, scale-to-zero serverless containers on Kubernetes.

## Core concepts
- **CaaS (Containers as a Service)**: container-based virtualization that abstracts infrastructure and orchestration. Good for simpler/smaller architectures that don't justify full Kubernetes overhead.
- **Serverless for containers**: you declare *what* to run. The platform handles placement, scaling (0→N in seconds), and infra. You pay for *consumption*, not *allocation*.
- **Amazon ECS**: AWS container orchestrator using Docker under the hood. Deploys to **EC2** (VM-based, you pay for provisioned instances) or **AWS Fargate** (serverless, pay per CPU/memory consumed).
- **ECS task**: ECS equivalent of a Kubernetes pod, one or more related containers. Finite process, runs once. Lifecycle: **Pending → Running → Stopped** (startup error jumps Pending → Stopped directly).
- **ECS service**: groups/maintains tasks, like a Kubernetes ReplicaSet/controller, keeps a desired count of tasks running. Use for long-running apps (web servers). Use plain tasks for batch jobs.
- **Task definition**: YAML blueprint for a task, very similar to (and compatible with) `docker-compose` files. Defines images, resources, ports, volumes, networking, launch type.
- **ECS node agent**: runs in an EC2 instance, reports container/task state to the ECS scheduler and drives the container runtime, analogous to `kubelet`.
- **ENI (Elastic Network Interface)**: every task gets one attached.
- **Knative**: CNCF open-source, vendor-agnostic serverless framework on top of Kubernetes. Runs as a Kubernetes operator via CRDs, managed by `kubectl` (ops) and `kn` (developers). Scales workload pods **from zero**: spins up a pod on first request, terminates after ~1 min idle. Two modules: **serving** (stateless HTTP/S apps) and **eventing** (Kafka, Google Pub/Sub). Google Cloud Run is built on Knative.
- **Knative endpoint** format: `<app-name>.<namespace>.<custom-domain>`. `custom-domain` is yours, or a MagicDNS service like **sslip.io** (e.g. `35.226.198.46.sslip.io` resolves to `35.226.198.46`) for experimentation only.

## Tools and versions
- **AWS CLI**: `aws-cli/1.22.34`, installed as a `deb`/`apt` package. Manages AWS resources, IAM, ELB, CloudWatch logs.
- **ECS CLI** (`ecs-cli`): `version 1.21.0`. Standalone binary, administers ECS clusters and tasks/services using docker-compose-style syntax.
- **CloudFormation**: AWS IaC engine. `ecs-cli up` provisions a stack (VPC, subnets, route table, IGW, security group, IAM role, instance profile, launch config, ASG, cluster) behind the scenes.
- **gcloud**: Google Cloud CLI, used to create GKE clusters (free trial $300/90 days).
- **kubectl**: applies Knative CRDs and manifests.
- **Knative serving**: `knative-v1.10.2` (CRDs, core, default-domain, hpa), net-istio `knative-v1.10.1`, `kn` client `knative-v1.10.0`.
- **Istio**: installed with `--set profile=demo`, and provides the Ingress Gateway that fronts Knative services. Knative also uses Prometheus/Grafana and eventing engines (Kafka, Google Pub/Sub).
- **hey**: HTTP load-testing utility used to trigger Knative autoscaling.
- Container base images in examples: `nginx`, `python:3.7-slim`. ECS AMI: Amazon Linux 2 with ECS Agent 1.72.0, Docker 20.10.23.

## Workflows (how-to)

### Repo setup
```bash
$ git clone https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git \
  modern-devops
$ cd modern-devops/ch7
# Replace placeholder Docker Hub user across files:
$ find ./ -type f -exec sed -i -e \
  's/<your_dockerhub_user>/<your actual docker hub user>/g' {} \;
```

### Install the AWS and ECS CLIs and authenticate
```bash
$ sudo apt update && sudo apt install awscli -y
$ aws --version

$ sudo curl -Lo /usr/local/bin/ecs-cli \
  https://amazon-ecs-cli.s3.amazonaws.com/ecs-cli-linux-amd64-latest
$ sudo chmod +x /usr/local/bin/ecs-cli
$ ecs-cli --version

# Authenticate ecs-cli via AWS env vars:
$ export AWS_SECRET_ACCESS_KEY=...
$ export AWS_ACCESS_KEY_ID=...
$ export AWS_DEFAULT_REGION=...
```

### Spin up an ECS cluster (with EC2 instances)
```bash
# Generate a key pair to SSH into EC2 instances:
$ aws ec2 create-key-pair --key-name ecs-keypair
# Save the JSON keyMaterial to ecs-keypair.pem, converting \n to real newlines.

# Create a 2-node t2.micro cluster (provisions a full CloudFormation stack):
$ ecs-cli up --keypair ecs-keypair --instance-type t2.micro \
  --size 2 --cluster cluster-1 --capability-iam
```
Save the output: it lists the created VPC, security group, and subnet IDs needed for Fargate and load balancing.

### Define and schedule an EC2 task
1. `cd ~/modern-devops/ch7/ECS/tasks/EC2/`
2. `docker-compose.yml` (the task definition):
```yaml
version: '3'
services:
  web:
    image: nginx
    ports:
      - "80:80"
    logging:
      driver: awslogs
      options:
        awslogs-group: /aws/webserver
        awslogs-region: us-east-1
        awslogs-stream-prefix: ecs
```
3. `ecs-params.yaml` (resources: `cpu_shares` in millicores, `mem_limit` in bytes):
```yaml
version: 1
task_definition:
  services:
    web:
      cpu_shares: 100
      mem_limit: 524288000
```
4. Schedule, then inspect, the task:
```bash
$ ecs-cli compose up --create-log-groups --cluster cluster-1 --launch-type EC2
$ ecs-cli ps --cluster cluster-1
$ curl <task-ip>:80
```

### Scale, log, and stop EC2 tasks
```bash
$ ecs-cli compose scale 2 --cluster cluster-1 --launch-type EC2   # horizontal scale
$ ecs-cli ps --cluster cluster-1

# Query CloudWatch logs (logStreamName = <prefix>/<task_name>/<task_id>):
$ aws logs describe-log-streams --log-group-name /aws/webserver \
  --log-stream-name-prefix ecs | grep logStreamName
$ aws logs get-log-events --log-group-name /aws/webserver \
  --log-stream ecs/web/<task_id>

$ ecs-cli compose down --cluster cluster-1   # stop tasks
```

### Schedule a Fargate task
Fargate requires the `awsvpc` network mode (default bridge fails with `Fargate only supports network mode 'awsvpc'`).
1. `cd ~/modern-devops/ch7/ECS/tasks/FARGATE/`
2. Create `task-execution-assume-role.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": { "Service": "ecs-tasks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```
3. Create the role and attach the managed execution policy:
```bash
$ aws iam --region us-east-1 create-role --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://task-execution-assume-role.json
$ aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  --role-name ecsTaskExecutionRole
```
4. `ecs-params.yml` (use *your* cluster's subnets and security group):
```yaml
version: 1
task_definition:
  task_execution_role: ecsTaskExecutionRole
  ecs_network_mode: awsvpc
  task_size:
    mem_limit: 0.5GB
    cpu_limit: 256
run_params:
  network_configuration:
    awsvpc_configuration:
      subnets:
        - "subnet-088b52c91a6f40fd7"
        - "subnet-032cd63290da67271"
      security_groups:
        - "sg-097206175813aa7e7"
      assign_public_ip: ENABLED
```
5. Launch / verify / tear down:
```bash
$ ecs-cli compose up --create-log-groups --cluster cluster-1 --launch-type FARGATE
$ ecs-cli ps --cluster cluster-1
$ curl <task-ip>:80
$ ecs-cli compose down --cluster cluster-1
```

### Run a long-running ECS service (Fargate)
```bash
$ ecs-cli compose service up --create-log-groups \
  --cluster cluster-1 --launch-type FARGATE
$ ecs-cli ps --cluster cluster-1

# Browse logs for a task by ID (single pane of glass, regardless of log store):
$ ecs-cli logs --task-id <task_id> --cluster cluster-1

$ ecs-cli compose service down --cluster cluster-1   # delete the service
```

### Load balance ECS tasks with an ALB (Layer 7)
```bash
# 1. Create the ALB (capture LoadBalancerARN and DNSName):
$ aws elbv2 create-load-balancer --name ecs-alb --subnets <SUBNET-1> <SUBNET-2> \
  --security-groups <SECURITY_GROUP_ID> --region us-east-1

# 2. Create a target group (capture targetGroupARN):
$ aws elbv2 create-target-group --name target-group --protocol HTTP \
  --port 80 --target-type ip --vpc-id <VPC_ID> --region us-east-1

# 3. Create a listener forwarding to the target group:
$ aws elbv2 create-listener --load-balancer-arn <LOAD_BALANCER_ARN> \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=<TARGET_GROUP_ARN> \
  --region us-east-1

# 4. Deploy service wired to the target group, then scale:
$ cd ~/modern-devops/ch7/ECS/loadbalancing/
$ ecs-cli compose service up --create-log-groups --cluster cluster-1 \
  --launch-type FARGATE --target-group-arn <TARGET_GROUP_ARN> \
  --container-name web --container-port 80
$ ecs-cli compose service scale 3 --cluster cluster-1

# 5. Hit the ALB DNS:
$ curl ecs-alb-1660189891.us-east-1.elb.amazonaws.com
```

### Spin up a GKE cluster (for Knative)
```bash
$ gcloud services enable container.googleapis.com
$ gcloud container clusters create cluster-1 --num-nodes 2 \
  --enable-autoscaling --min-nodes 1 --max-nodes 5 --zone us-central1-a
```

### Install Knative (serving) + Istio on Kubernetes
```bash
$ cd ~/modern-devops/ch7/knative/

# CRDs + core serving:
$ kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.10.2/serving-crds.yaml
$ kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.10.2/serving-core.yaml

# Istio:
$ curl -L https://istio.io/downloadIstio | sh -
$ sudo mv istio-*/bin/istioctl /usr/local/bin
$ istioctl install --set profile=demo -y

# Wait for the Ingress Gateway external IP:
$ kubectl -n istio-system get service istio-ingressgateway

# Knative Istio controller, MagicDNS (sslip.io) default domain, and HPA add-on:
$ kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.10.1/net-istio.yaml
$ kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.10.2/serving-default-domain.yaml
$ kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.10.2/serving-hpa.yaml

# kn CLI:
$ sudo curl -Lo /usr/local/bin/kn \
  https://github.com/knative/client/releases/download/knative-v1.10.0/kn-linux-amd64
$ sudo chmod +x /usr/local/bin/kn
```

### Build and deploy a Flask app on Knative
1. `app.py` and `Dockerfile` (see Reference snippets), then:
```bash
$ docker build -t <your_dockerhub_user>/py-time .
$ docker push <your_dockerhub_user>/py-time
```
2. Imperative deploy with `kn`:
```bash
$ kn service create py-time --image <your_dockerhub_user>/py-time
# -> http://py-time.default.<INGRESS_IP>.sslip.io
$ curl http://py-time.default.35.226.198.46.sslip.io
$ kn service delete py-time
```
3. Declarative deploy with a Knative `Service` CRD (`py-time-deploy.yaml`):
```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: py-time
spec:
  template:
    spec:
      containers:
        - image: <your_dockerhub_user>/py-time
```
```bash
$ kubectl apply -f py-time-deploy.yaml
$ kubectl get ksvc py-time      # shows the URL
$ curl http://py-time.default.35.226.198.46.sslip.io
```
4. Observe scale-to-zero: `kubectl get pod -w` shows the pod `Terminating` ~1 min after the last request.

### Load test Knative to trigger autoscaling
```bash
$ hey -z 30s -c 500 http://py-time.default.35.226.198.46.sslip.io
$ kubectl get pod     # multiple py-time-* pods (e.g. 7) appear
$ kubectl get nodes   # GKE adds nodes to the pool under load
```

## Reference snippets

### Flask app (`app.py`)
```python
import os
import datetime
from flask import Flask
app = Flask(__name__)
@app.route('/')
def current_time():
  ct = datetime.datetime.now()
  return 'The current time is : {}!\n'.format(ct)
if __name__ == "__main__":
  app.run(debug=True,host='0.0.0.0')
```

### Dockerfile (gunicorn, Knative-ready, binds to $PORT)
```dockerfile
FROM python:3.7-slim
ENV PYTHONUNBUFFERED True
ENV APP_HOME /app
WORKDIR $APP_HOME
COPY . ./
RUN pip install Flask gunicorn
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
```

### AmazonECSTaskExecutionRolePolicy (what the managed policy grants)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

## Decision guidance and best practices
- **EC2 vs Fargate launch type**: run long-running online tasks (e.g. web servers) on **EC2** (cheaper for sustained load). Run **batch** tasks on **Fargate** (pay only for consumption during the short run). Fargate is more expensive for long-running services.
- **Tasks vs services**: use **services** for long-running apps (web servers) so failed tasks get replaced. Use plain **tasks** for batch jobs you don't want recreated after they finish.
- **ECS vs Kubernetes (EKS/AKS/GKE)**: choose **ECS** if you run exclusively on AWS with no multi-cloud/hybrid plans and want low orchestration overhead. Choose a managed Kubernetes (EKS/AKS/GKE) to use the open, portable Kubernetes API and avoid vendor lock-in (costs +$0.10/hour cluster management on all three).
- **GKE** is generally first to roll out new Kubernetes versions and security patches (Google originated the project) and is the most feature-rich/customizable.
- **Google Cloud Run** = fully managed serverless CaaS on Knative. Use it on Google Cloud for a minimal-Ops/NoOps option without Kubernetes complexity.
- **ALB (Layer 7) vs NLB (Layer 4)**: prefer the **ALB** for HTTP apps, it supports path-based and host-based routing.
- Prefer `docker-compose`-format task definitions to align with an open standard.
- Use IAM with least privilege (PoLP) and RBAC for ECS task roles.
- **Knative** gives scale-to-zero (no idle instances per microservice) on portable Kubernetes. Combine with cluster node autoscaling for full elastic, vendor-agnostic serverless.

## Pitfalls and gotchas
- **Fargate network mode**: omitting `awsvpc` causes `ClientException: Fargate only supports network mode 'awsvpc'`. Set `ecs_network_mode: awsvpc` in `ecs-params.yml`.
- **Key pair file**: when saving `ecs-keypair.pem` from the JSON output, replace literal `\n` with real newlines or SSH will reject the key.
- **Copy your own IDs**: use the subnets and security group of *your* ECS cluster (from `ecs-cli up` output) in Fargate `ecs-params.yml` and ALB commands. Don't copy the book's example IDs.
- **Tasks run once**: a stopped task cannot be restarted. You need a service to keep tasks alive.
- **Scaled tasks have separate IPs**: multiple task instances each get their own IP, front them with a load balancer for a single endpoint.
- **MagicDNS (sslip.io) is experimental**: never use it in production. Configure real DNS resolving to the Istio Ingress Gateway IP instead.
- **Knative `Service` ≠ Kubernetes `Service`**: the Knative resource is `apiVersion: serving.knative.dev/v1`. `apiVersion` is what disambiguates it.
- **Cost awareness**: ECS on EC2 bills for provisioned instances even when idle. EKS/AKS/GKE add $0.10/hour cluster management.

## Command / API cheat-sheet
- `aws ec2 create-key-pair --key-name ecs-keypair`: create SSH key pair for EC2 nodes.
- `ecs-cli up --keypair ... --instance-type ... --size N --cluster ... --capability-iam`: provision an ECS cluster + CloudFormation stack.
- `ecs-cli compose up --cluster ... --launch-type EC2|FARGATE`: schedule a task.
- `ecs-cli compose scale N --cluster ... --launch-type ...`: horizontally scale tasks.
- `ecs-cli compose down --cluster ...`: stop tasks.
- `ecs-cli compose service up/down/scale ... --cluster ...`: manage a long-running service.
- `ecs-cli ps --cluster ...`: list tasks with IPs/ports/state.
- `ecs-cli logs --task-id <id> --cluster ...`: view task logs via ECS CLI.
- `aws logs describe-log-streams / get-log-events --log-group-name ...`: read CloudWatch logs.
- `aws iam create-role / attach-role-policy`: set up the ECS task execution role.
- `aws elbv2 create-load-balancer / create-target-group / create-listener`: build an ALB front end.
- `gcloud container clusters create ... --enable-autoscaling --min-nodes --max-nodes`: create autoscaling GKE cluster.
- `istioctl install --set profile=demo -y`: install Istio for Knative.
- `kn service create|delete <name> --image <img>`: imperative Knative deploy.
- `kubectl apply -f <knative-service>.yaml`: declarative Knative deploy.
- `kubectl get ksvc <name>`: get a Knative service's URL.
- `hey -z 30s -c 500 <url>`: load test to trigger autoscaling.

## Where this is covered (topic index)
- ECS architecture / AWS terms (Region, AZ, VPC, subnet, route table, IGW, IAM, ASG, CloudWatch) -> "Core concepts", "ECS architecture"
- Install AWS CLI / ECS CLI, authenticate -> "Install the AWS and ECS CLIs and authenticate"
- Create an ECS cluster / CloudFormation stack -> "Spin up an ECS cluster"
- ECS task definition / docker-compose / ecs-params -> "Define and schedule an EC2 task"
- EC2 launch type, scaling tasks, CloudWatch logs, stopping tasks -> "Schedule / Scale, log, and stop EC2 tasks"
- Fargate launch type, awsvpc, task execution role -> "Schedule a Fargate task"
- ECS service (ReplicaSet equivalent), long-running apps -> "Run a long-running ECS service"
- Load balancing, ALB vs NLB, target group, listener -> "Load balance ECS tasks with an ALB"
- ECS vs EKS vs AKS vs GKE vs Cloud Run, vendor lock-in, pricing -> "Other CaaS / Decision guidance"
- Knative architecture, serving vs eventing, scale-to-zero, sslip.io / MagicDNS -> "Core concepts", "Knative" workflows
- Install Knative + Istio, kn CLI, GKE -> "Spin up a GKE cluster", "Install Knative"
- Deploy Flask app, Knative Service CRD, ksvc -> "Build and deploy a Flask app on Knative", "Reference snippets"
- Horizontal autoscaling, load testing with hey, node pool autoscaling -> "Load test Knative to trigger autoscaling"
- Serverless rationale, pay-per-use -> "The need for serverless offerings" (Core concepts)
