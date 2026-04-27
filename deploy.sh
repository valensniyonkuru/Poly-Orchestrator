#!/usr/bin/env bash
# =============================================================================
# ShopNow — Full Deployment Script
# Builds images, pushes to ECR, deploys to ECS + EKS
# Usage: ./deploy.sh <aws-account-id> <region> [ecs|eks|all]
# =============================================================================
set -euo pipefail

AWS_ACCOUNT_ID="${1:?Usage: ./deploy.sh <aws-account-id> <region> [ecs|eks|all]}"
AWS_REGION="${2:-us-east-1}"
TARGET="${3:-all}"

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FRONTEND_REPO="shopnow-frontend"
BACKEND_REPO="shopnow-backend"
TAG="latest"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
die()  { echo -e "${RED}[ERROR] $*${NC}"; exit 1; }

# ── Check prerequisites ───────────────────────────────────────────────────────
for cmd in aws docker kubectl terraform; do
  command -v "$cmd" &>/dev/null || die "Required tool '$cmd' not found"
done
log "Prerequisites: OK"

# ── Authenticate to ECR ───────────────────────────────────────────────────────
log "Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# ── Create ECR repos if they don't exist ─────────────────────────────────────
for repo in "$FRONTEND_REPO" "$BACKEND_REPO"; do
  aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$repo" \
    &>/dev/null || aws ecr create-repository --region "$AWS_REGION" --repository-name "$repo"
done
log "ECR repositories: ready"

# ── Build & push Docker images ───────────────────────────────────────────────
log "Building frontend image..."
docker build -t "$FRONTEND_REPO:$TAG" ./frontend
docker tag "$FRONTEND_REPO:$TAG" "$ECR_REGISTRY/$FRONTEND_REPO:$TAG"
docker push "$ECR_REGISTRY/$FRONTEND_REPO:$TAG"
log "Frontend pushed: $ECR_REGISTRY/$FRONTEND_REPO:$TAG"

log "Building backend image..."
docker build -t "$BACKEND_REPO:$TAG" ./backend
docker tag "$BACKEND_REPO:$TAG" "$ECR_REGISTRY/$BACKEND_REPO:$TAG"
docker push "$ECR_REGISTRY/$BACKEND_REPO:$TAG"
log "Backend pushed: $ECR_REGISTRY/$BACKEND_REPO:$TAG"

# ── Terraform provisioning ───────────────────────────────────────────────────
log "Running Terraform..."
cd terraform
terraform init -upgrade
terraform plan \
  -var="ecr_frontend_image=$ECR_REGISTRY/$FRONTEND_REPO:$TAG" \
  -var="ecr_backend_image=$ECR_REGISTRY/$BACKEND_REPO:$TAG" \
  -out=tfplan
terraform apply -auto-approve tfplan
ECS_ALB=$(terraform output -raw ecs_alb_dns)
EKS_CLUSTER=$(terraform output -raw eks_cluster_name)
cd ..

# ── ECS deployment ────────────────────────────────────────────────────────────
if [[ "$TARGET" == "ecs" || "$TARGET" == "all" ]]; then
  log "Forcing ECS service updates..."
  aws ecs update-service \
    --cluster shopnow-dev-cluster \
    --service shopnow-dev-frontend \
    --force-new-deployment \
    --region "$AWS_REGION" >/dev/null
  aws ecs update-service \
    --cluster shopnow-dev-cluster \
    --service shopnow-dev-backend \
    --force-new-deployment \
    --region "$AWS_REGION" >/dev/null
  log "ECS deployment triggered. ALB: http://$ECS_ALB"
fi

# ── EKS deployment ────────────────────────────────────────────────────────────
if [[ "$TARGET" == "eks" || "$TARGET" == "all" ]]; then
  log "Updating kubeconfig for EKS..."
  aws eks update-kubeconfig \
    --region "$AWS_REGION" \
    --name "$EKS_CLUSTER"

  log "Updating image references in manifests..."
  sed -i "s|YOUR_ECR_URI|$ECR_REGISTRY|g" k8s/04-backend.yaml k8s/05-frontend.yaml

  log "Applying Kubernetes manifests..."
  kubectl apply -f k8s/ --namespace shopnow || kubectl apply -f k8s/

  log "Waiting for rollout..."
  kubectl rollout status deployment/frontend -n shopnow --timeout=300s
  kubectl rollout status deployment/backend  -n shopnow --timeout=300s

  EKS_LB=$(kubectl get ingress shopnow-ingress -n shopnow -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
  log "EKS deployment complete. Ingress: http://$EKS_LB"
fi

echo ""
log "========== DEPLOYMENT SUMMARY =========="
log "ECS Frontend URL : http://${ECS_ALB:-N/A}"
log "EKS Ingress URL  : http://${EKS_LB:-N/A}"
log "========================================"
