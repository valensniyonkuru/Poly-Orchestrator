# Poly-Orchestrator — AWS ECS vs EKS Benchmark Project

> **Multi-Cloud Container Orchestration Project** | Comprehensive DevOps solution demonstrating both AWS ECS (Fargate) and Kubernetes (EKS) deployment strategies for a scalable e-commerce platform. Includes full Infrastructure as Code, service discovery, load balancing, and production-grade resiliency testing.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Project Overview](#project-overview)
3. [Prerequisites](#prerequisites)
4. [Project Structure](#project-structure)
5. [Part 1: Local Development with Docker Compose](#part-1-local-development)
6. [Remote State Setup (First-time only)](#remote-state-setup-first-time-only)
7. [Part 2: Infrastructure as Code with Terraform](#part-2-terraform)
8. [Part 3: ECS Fargate Deployment](#part-3-ecs-deployment)
9. [Part 4: EKS Deployment](#part-4-eks-deployment)
10. [Part 5: Resiliency Testing](#part-5-resiliency-testing)
11. [Part 6: Testing](#part-6-testing)
12. [ECS vs EKS Comparison](#ecs-vs-eks-comparison)
13. [Troubleshooting](#troubleshooting)

---

## Project Overview

**Poly-Orchestrator** is an enterprise-grade DevOps engineering project designed to benchmark and compare two major AWS container orchestration platforms:

- **Amazon ECS (Fargate)** — Simplified, AWS-native container management
- **Amazon EKS (Kubernetes)** — Cloud-native, portable container orchestration

This project implements a complete, production-ready deployment of a multi-tier e-commerce platform on both platforms, allowing direct comparison of deployment complexity, operational burden, scalability, and cost.

---

## Architecture Overview

Poly-Orchestrator uses a 3-tier e-commerce application architecture:

```
Internet
    │
    ▼
[ Application Load Balancer ]
    │
    ▼
[ Frontend — Flask/Python — Port 5000 ]
    │  (talks to backend via service discovery)
    ▼
[ Backend API — Flask/Python — Port 5000 ]
    ├──▶ [ Redis 7 — Port 6379 ]  (session/cart caching)
    └──▶ [ Postgres 16 — Port 5432 ]  (orders, products)
```

**ECS Path:** ALB → Fargate tasks → Cloud Map DNS (`backend.shopnow.local`)  
**EKS Path:** ALB Ingress → ClusterIP Services → CoreDNS (`backend-service.shopnow.svc.cluster.local`)

### Docker Containerization

Both `frontend/Dockerfile` and `backend/Dockerfile` use a **two-stage build**:

| Stage | Base | Purpose |
|---|---|---|
| `builder` | `python:3.11-slim` | Installs build tools (`gcc`, `libpq-dev`) and compiles Python packages into `/install` |
| runtime | `python:3.11-slim` | Copies only `/install` from builder — no compiler or headers in the final image |

Containers run as non-root user `appuser` (`adduser --disabled-password`). The `gunicorn` server is invoked via `python -m gunicorn` so it resolves through `PYTHONPATH=/install` without needing a system-level entry point.

![Docker Images](./images/dockerImages.png)

![Docker Container](./images/dockerContainer.png)

### Database Architecture

![Database Schema](./images/database.png)

### Frontend Interface

![Frontend Application](./images/frontend.png)

## Prerequisites

| Tool         | Version   | Install                                      |
|--------------|-----------|----------------------------------------------|
| AWS CLI      | >= 2.x    | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| Docker       | >= 24.x   | https://docs.docker.com/get-docker/          |
| Terraform    | >= 1.5.0  | https://developer.hashicorp.com/terraform/install |
| kubectl      | >= 1.29   | https://kubernetes.io/docs/tasks/tools/      |
| git          | any       | https://git-scm.com/                         |
| Helm         | >= 3.x    | https://helm.sh/docs/intro/install/          |

**AWS Permissions Required:**  
`AmazonECS_FullAccess`, `AmazonEKSFullAccess`, `AmazonEC2FullAccess`, `AmazonVPCFullAccess`, `AmazonECRFullAccess`, `CloudWatchFullAccess`, `IAMFullAccess`, `AWSCloudMapFullAccess`

---

## Project Structure

```
Poly-Orchestrator/
├── .env.example                # Template for required env vars — copy to .env
├── .github/
│   └── workflows/
│       └── test.yml            # CI: pytest + coverage gate (≥70%)
│
├── frontend/                   # Flask frontend app
│   ├── app.py                  # Application code
│   ├── templates/index.html    # UI template
│   ├── requirements.txt        # Python deps
│   └── Dockerfile              # Multi-stage build, non-root appuser
│
├── backend/                    # Flask backend API
│   ├── app.py                  # REST API with Redis + Postgres
│   ├── requirements.txt
│   ├── requirements-test.txt   # pytest, pytest-flask, pytest-mock, coverage
│   ├── pytest.ini              # testpaths = tests, pythonpath = .
│   ├── Dockerfile              # Multi-stage build, non-root appuser
│   └── tests/
│       ├── conftest.py         # Shared fixtures (app, client, mock_redis, mock_db)
│       ├── test_health.py      # Unit tests for GET /health
│       └── test_api.py         # Integration tests for all API routes
│
├── docker/
│   └── init.sql                # Postgres schema + seed data
│
├── images/                     # Architecture diagrams and screenshots
│   ├── dockerImages.png
│   ├── dockerContainer.png
│   ├── database.png
│   └── frontend.png
│
├── docker-compose.yml          # Local dev environment
│
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                 # Root module — wires VPC + ECS + EKS, S3 backend
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── bootstrap/
│   │   └── main.tf             # One-time: provisions S3 bucket + DynamoDB lock table
│   └── modules/
│       ├── vpc/                # VPC, subnets, NAT, routing
│       ├── ecs/                # ECS cluster, tasks, services, ALB, Cloud Map, SSM
│       └── eks/                # EKS cluster, node groups, add-ons
│
├── k8s/                        # Kubernetes manifests
│   ├── 00-namespace.yaml
│   ├── 01-configmap-secret.yaml    # ConfigMap only — no plaintext secrets
│   ├── 01-external-secret.yaml     # ESO SecretStore + ExternalSecret for DB_PASSWORD
│   ├── 02-redis.yaml
│   ├── 03-postgres.yaml
│   ├── 04-backend.yaml             # Deployment + Service + HPA
│   ├── 05-frontend.yaml            # Deployment + Service + HPA
│   ├── 06-ingress.yaml             # AWS ALB Ingress Controller
│   └── 07-network-policy.yaml      # Pod-level firewall rules
│
├── deploy.sh                   # Full build + deploy script
├── resiliency-test.sh          # Kill container/pod + verify recovery
└── README.md                   # This file
```

---

## Part 1: Local Development

### Step 0 — Configure environment variables

The backend exits at startup if `DB_PASSWORD` is not set. Copy the example file and fill in a local password before running any services.

```bash
cp .env.example .env
# Edit .env — set at minimum: DB_PASSWORD=<any local password>
```

### Step 1 — Clone and run locally

```bash
git clone <your-repo-url>
cd shopnow

# Verify Docker is running
docker info

# Build and start all 4 services
docker compose up --build -d

# Check all services are healthy
docker compose ps
```

**Expected output:**
```
NAME         STATUS          PORTS
frontend     Up (healthy)    0.0.0.0:5000->5000/tcp
backend      Up (healthy)    0.0.0.0:5000->5000/tcp
redis        Up (healthy)    0.0.0.0:6379->6379/tcp
postgres     Up (healthy)    0.0.0.0:5432->5432/tcp
```

### Step 2 — Verify the application

```bash
# Visit the UI
open http://localhost:5000

# Check frontend health
curl http://localhost:5000/health

# Check backend health (includes Redis + Postgres status)
curl http://localhost:5000/health | python3 -m json.tool

# Load products (served from DB, cached in Redis)
curl http://localhost:5000/products | python3 -m json.tool

# Add item to cart (stored in Redis) — product_id is required
curl -X POST http://localhost:5000/cart/add \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "name": "Wireless Headphones", "price": 79.99}'

# Create an order (stored in Postgres)
curl -X POST http://localhost:5000/orders \
  -H "Content-Type: application/json" \
  -d '{"product_name": "Wireless Headphones", "quantity": 1, "total": 79.99}'

# View orders from Postgres
curl http://localhost:5000/orders | python3 -m json.tool
```

### Step 3 — Stop local environment

```bash
docker compose down -v   # -v also removes named volumes
```

---

## Remote State Setup (First-time only)

> **Run this once** before the main Terraform configuration. It provisions
> the S3 bucket and DynamoDB table that store and lock the shared Terraform state.
> Skip this section if the bucket `shopnow-tfstate` already exists in your account.

### Step 1 — Provision the backend infrastructure

```bash
cd terraform/bootstrap
terraform init
terraform apply
# Creates: S3 bucket "shopnow-tfstate" (versioned, AES256 encrypted, all-public-access blocked)
#          DynamoDB table "shopnow-tf-lock" (PAY_PER_REQUEST, LockID hash key)
```

### Step 2 — Migrate state to S3

```bash
cd ../          # back to terraform/
terraform init
# Terraform detects the backend "s3" block and prompts:
#   "Do you want to copy existing state to the new backend? yes"
# Local terraform.tfstate is uploaded to s3://shopnow-tfstate/shopnow/terraform.tfstate
```

### Step 3 — Deploy infrastructure

```bash
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

> **Note:** All subsequent `terraform plan` / `apply` / `destroy` runs by any
> team member will read and write state from S3. The DynamoDB table prevents
> two applies from running simultaneously.

---

## Part 2: Terraform

### Step 1 — Configure credentials and variables

```bash
# Configure AWS CLI
aws configure
# Enter: Access Key ID, Secret Key, Region (us-east-1), Output (json)

# Verify
aws sts get-caller-identity

# Set up Terraform variables
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your ECR image URIs, DB password, region
```

### Step 2 — Initialize and preview

```bash
terraform init

terraform validate

terraform plan \
  -var="ecr_frontend_image=placeholder" \
  -var="ecr_backend_image=placeholder"
# Review: VPC, 3 public subnets, 3 private subnets, 1 NAT gateway,
#         ECS cluster, EKS cluster, IAM roles, security groups, ALB
```

### Step 3 — Apply (NOTE: costs apply)

```bash
# Full apply done automatically by deploy.sh
# Or manually:
terraform apply -var-file=terraform.tfvars
```

**Resources created:**
- 1 VPC with 3 public + 3 private subnets across 3 AZs
- 1 NAT Gateway (dev/lab; use 3 — one per AZ — for production HA)
- 1 ECS Cluster (Fargate + Fargate Spot)
- 1 EKS Cluster (v1.29) with managed node group (2× t3.medium)
- 1 Application Load Balancer (public-facing)
- Cloud Map private DNS namespace (`shopnow.local`)
- SSM SecureString parameter `/shopnow/db_password` for backend DB credentials
- IAM **execution role** (ECS agent: ECR pull, CloudWatch logs, SSM secret injection)
- IAM **task role** (application code: read SSM parameters and Secrets Manager at runtime)
- IAM roles for EKS nodes
- CloudWatch log groups

---

## Part 3: ECS Deployment

### How it works

```
Internet → ALB (port 80)
              │
              ▼
    [frontend task — Fargate]
    BACKEND_URL=http://backend.shopnow.local:5000
              │  (Cloud Map DNS resolution)
              ▼
    [backend task — Fargate]
              ├──▶ redis.shopnow.local:6379
              └──▶ postgres.shopnow.local:5432
```

**Service Discovery:** AWS Cloud Map registers each Fargate task's private IP under `backend.shopnow.local`. The frontend resolves this DNS name — no hardcoded IPs.

**Secrets:** `DB_PASSWORD` is stored as an SSM SecureString at `/shopnow/db_password` (AES256 encrypted at rest). The ECS task definition uses a `secrets` block to inject it into the container at launch — the plaintext value is never written into task definition JSON or CloudTrail logs.

**IAM roles:** Two roles are created per task family:
- **Execution role** — assumed by the ECS agent; needs SSM `GetParameters` permission to resolve the `secrets` block before the container starts.
- **Task role** — assumed by the application code; grants `ssm:GetParameter`, `secretsmanager:GetSecretValue`, and `kms:Decrypt` scoped to the DB password parameter.

### Step 1 — Build and push images

```bash
cd shopnow

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"
ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ECR

# Create repos
aws ecr create-repository --repository-name shopnow-frontend --region $AWS_REGION
aws ecr create-repository --repository-name shopnow-backend  --region $AWS_REGION

# Build and push
docker build -t shopnow-frontend ./frontend
docker tag  shopnow-frontend $ECR/shopnow-frontend:latest
docker push $ECR/shopnow-frontend:latest

docker build -t shopnow-backend ./backend
docker tag  shopnow-backend $ECR/shopnow-backend:latest
docker push $ECR/shopnow-backend:latest
```

### Step 2 — Deploy (via deploy.sh)

```bash
chmod +x deploy.sh
./deploy.sh $AWS_ACCOUNT_ID $AWS_REGION ecs
```

### Step 3 — Verify ECS deployment

```bash
# List running tasks
aws ecs list-tasks --cluster shopnow-dev-cluster --region us-east-1

# Describe a service
aws ecs describe-services \
  --cluster shopnow-dev-cluster \
  --services shopnow-dev-frontend \
  --region us-east-1 \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount}'

# View logs
aws logs tail /ecs/shopnow-dev/frontend --follow --region us-east-1

# Get ALB DNS
terraform -chdir=terraform output ecs_alb_dns
# Visit: http://<alb-dns>
```

---

## Part 4: EKS Deployment

### How it works

```
Internet → AWS ALB (via ALB Ingress Controller)
              │
              ├─/api/* ──▶ backend-service:5000 (ClusterIP)
              │                    │
              └─/*     ──▶ frontend-service:80  (ClusterIP)
                                  │
                         BACKEND_URL=http://backend-service:5000
```

**Service Discovery:** Kubernetes CoreDNS resolves `backend-service.shopnow.svc.cluster.local`. Services use stable ClusterIP addresses — pods behind them can scale freely.

**Secrets:** `DB_PASSWORD` is managed by the [External Secrets Operator](https://external-secrets.io/) (ESO). `k8s/01-external-secret.yaml` defines a `SecretStore` pointing to AWS Secrets Manager and an `ExternalSecret` that materialises a native Kubernetes `Secret` at runtime. No plaintext credentials are stored in any manifest.

### Step 1 — Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name shopnow-dev-eks

kubectl cluster-info
kubectl get nodes
```

### Step 2 — Install ALB Ingress Controller

```bash
# Install cert-manager (dependency)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

# Install AWS Load Balancer Controller
# See: https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=shopnow-dev-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### Step 3 — Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace
```

Then create the IAM role `shopnow-secrets-role` with `secretsmanager:GetSecretValue` on the DB password secret, and annotate its ARN in `k8s/01-external-secret.yaml` under the `ServiceAccount` resource before applying. See comments at the top of that file for the full setup checklist.

### Step 4 — Update image references

```bash
# Set ECR_REGISTRY, then substitute the placeholder in the manifests
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
envsubst < k8s/04-backend.yaml  | kubectl apply -f -
envsubst < k8s/05-frontend.yaml | kubectl apply -f -
```

### Step 5 — Apply remaining manifests

```bash
# Apply everything except the image-referencing files (already applied above)
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap-secret.yaml
kubectl apply -f k8s/01-external-secret.yaml
kubectl apply -f k8s/02-redis.yaml
kubectl apply -f k8s/03-postgres.yaml
kubectl apply -f k8s/06-ingress.yaml
kubectl apply -f k8s/07-network-policy.yaml

# Watch pods start
kubectl get pods -n shopnow -w

# Check services
kubectl get svc -n shopnow

# Check ingress (ALB DNS will appear after ~2 min)
kubectl get ingress -n shopnow
```

### Step 6 — Verify EKS deployment

```bash
# All pods running?
kubectl get pods -n shopnow

# Logs
kubectl logs -l app=frontend -n shopnow --tail=50
kubectl logs -l app=backend  -n shopnow --tail=50

# HPA status
kubectl get hpa -n shopnow

# Get ingress URL
kubectl get ingress shopnow-ingress -n shopnow \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## Part 5: Resiliency Testing

This test proves both platforms automatically recover from container/pod failure.

### Run the test

```bash
chmod +x resiliency-test.sh

# Test both platforms
./resiliency-test.sh both

# Or test individually
./resiliency-test.sh ecs
./resiliency-test.sh eks
```

### What the script does

**ECS Test:**
1. Lists running Fargate tasks for the frontend service
2. Records task count (baseline)
3. Force-stops one task (`aws ecs stop-task`)
4. Polls every 10 seconds for up to 3 minutes
5. Reports when task count returns to baseline
> ECS scheduler detects the stopped task and launches a replacement automatically (typically within 30–60 seconds).

**EKS Test:**
1. Lists running frontend pods
2. Records pod count (baseline)
3. Force-deletes one pod (`kubectl delete pod --force --grace-period=0`)
4. Polls every 10 seconds for up to 3 minutes
5. Reports when pod count returns to baseline
> Kubernetes ReplicaSet controller detects the missing pod and schedules a new one immediately (typically within 15–30 seconds).

### Manual resiliency commands

```bash
# ── ECS: manually kill a task ────────────────────────────────────────────────
TASK=$(aws ecs list-tasks \
  --cluster shopnow-dev-cluster \
  --service-name shopnow-dev-frontend \
  --query 'taskArns[0]' --output text)
aws ecs stop-task --cluster shopnow-dev-cluster --task $TASK

# Watch ECS Events (in another terminal)
aws ecs describe-services \
  --cluster shopnow-dev-cluster \
  --services shopnow-dev-frontend \
  --query 'services[0].events[:5]'

# ── EKS: manually kill a pod ─────────────────────────────────────────────────
POD=$(kubectl get pods -n shopnow -l app=frontend -o name | head -1)
kubectl delete $POD -n shopnow --force --grace-period=0

# Watch pod recovery (in another terminal)
kubectl get pods -n shopnow -l app=frontend -w
```

---

## Part 6: Testing

The backend ships with a full test suite under `backend/tests/`. Tests use the Flask test client with Redis and Postgres mocked out — no real AWS infrastructure required.

### Run tests locally

```bash
cd backend

# Install dependencies
pip install -r requirements.txt -r requirements-test.txt

# Run with coverage (DB_PASSWORD satisfies the startup guard — no real DB is touched)
DB_PASSWORD=testpassword coverage run --source=app -m pytest tests/ -v

# Print coverage report and fail if below 70%
coverage report --fail-under=70
```

### Test structure

| File | What it tests |
|---|---|
| `tests/conftest.py` | Shared fixtures: `app`, `client`, `mock_redis`, `mock_db` |
| `tests/test_health.py` | `GET /health` — status code, response body, degraded states |
| `tests/test_api.py` | All routes: products, cart (including 400 on missing `product_id`), orders |

### CI

`.github/workflows/test.yml` runs on every push and pull request to `main`:
1. Installs system deps (`libpq-dev` for psycopg2 compilation)
2. Installs `requirements.txt` + `requirements-test.txt`
3. Runs `coverage run --source=app -m pytest tests/ -v`
4. Runs `coverage report --fail-under=70` — build fails if coverage drops below 70%
5. Uploads `coverage.xml` as a build artifact

---

## ECS vs EKS Comparison

| Dimension              | ECS (Fargate)                        | EKS (Kubernetes)                        |
|------------------------|--------------------------------------|-----------------------------------------|
| **Setup complexity**   | Low — minutes                        | High — hours (IAM, add-ons, ingress)    |
| **Operational burden** | AWS manages control plane + workers  | AWS manages control plane only          |
| **Scaling**            | Service-level desired count + AS     | HPA + Cluster Autoscaler                |
| **Service discovery**  | AWS Cloud Map (DNS)                  | CoreDNS + ClusterIP Services            |
| **Load balancing**     | ALB natively integrated              | ALB via Ingress Controller (extra step) |
| **Networking**         | awsvpc (per-task ENI)                | VPC CNI (per-pod IP)                    |
| **Cost**               | Pay per vCPU/memory per second       | EC2 nodes (always-on) + control plane   |
| **Portability**        | AWS-only                             | Runs anywhere (GKE, AKS, on-prem)       |
| **Ecosystem**          | AWS-native tooling                   | CNCF ecosystem (Helm, Argo, Karpenter)  |
| **Best for**           | Simpler workloads, fast start        | Complex microservices, multi-cloud      |

**Recommendation for ShopNow:**  
Start with **ECS Fargate** for speed and simplicity. Migrate to **EKS** when you need advanced scheduling, multi-region portability, or a richer GitOps/Helm ecosystem.

---

## Troubleshooting

### ECS — tasks not starting

```bash
# Check service events
aws ecs describe-services \
  --cluster shopnow-dev-cluster \
  --services shopnow-dev-frontend \
  --query 'services[0].events[:10]'

# Check stopped task reason
aws ecs list-tasks --cluster shopnow-dev-cluster --desired-status STOPPED \
  | xargs -I{} aws ecs describe-tasks --cluster shopnow-dev-cluster --tasks {} \
    --query 'tasks[0].stoppedReason'
```

### ECS — frontend can't reach backend

```bash
# Verify Cloud Map service has instances
aws servicediscovery list-instances \
  --service-id <service-id-from-terraform-output>

# Test DNS resolution from a running task
aws ecs execute-command \
  --cluster shopnow-dev-cluster \
  --task <task-arn> \
  --container frontend \
  --interactive \
  --command "/bin/sh -c 'nslookup backend.shopnow.local'"
```

### ECS — backend exits immediately (DB_PASSWORD not set)

The backend process calls `sys.exit(1)` at startup if `DB_PASSWORD` is absent. Verify the SSM parameter exists and the execution role has `ssm:GetParameters` on its ARN:

```bash
aws ssm get-parameter --name /shopnow/db_password --with-decryption
```

### EKS — pods in CrashLoopBackOff

```bash
kubectl describe pod <pod-name> -n shopnow
kubectl logs <pod-name> -n shopnow --previous
```

### EKS — ExternalSecret not syncing

```bash
# Check ESO controller logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50

# Check ExternalSecret status
kubectl describe externalsecret shopnow-db-password -n shopnow
```

### EKS — ingress has no address

```bash
# Check ALB controller is running
kubectl get pods -n kube-system | grep aws-load-balancer

# Check ingress events
kubectl describe ingress shopnow-ingress -n shopnow
```

### Terraform — destroy resources to stop billing

```bash
cd terraform
terraform destroy -var-file=terraform.tfvars
```

> **WARNING:** This deletes ALL provisioned resources. Data in Postgres/Redis will be lost.

---

## Cost Estimate (us-east-1)

| Resource                     | Monthly Cost (approx.) |
|------------------------------|------------------------|
| EKS control plane            | ~$73                   |
| 2× t3.medium nodes (EKS)     | ~$60                   |
| 1× NAT Gateway (dev/lab)     | ~$35                   |
| 2× ALBs                      | ~$36                   |
| ECR storage                  | ~$1                    |
| CloudWatch logs              | ~$5                    |
| **Total estimate**           | **~$210/month**        |

> For production HA, use 3 NAT Gateways (one per AZ, ~$100/month) bringing the total to ~$275/month.  
> Destroy with `terraform destroy` when not in use to avoid charges.

---

*Project by ShopNow DevOps Engineering | CTO Benchmark: ECS vs EKS*
