#!/usr/bin/env bash
# =============================================================================
# ShopNow — Resiliency Test Script
# Kills containers/pods and verifies automatic recovery in ECS & EKS
# Usage: ./resiliency-test.sh [ecs|eks|both]
# =============================================================================
set -euo pipefail

TARGET="${1:-both}"
CLUSTER="shopnow-dev-cluster"
NAMESPACE="shopnow"
REGION="${AWS_REGION:-us-east-1}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] $*${NC}"; }
step() { echo -e "${CYAN}[STEP] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }

# ── ECS Resiliency Test ───────────────────────────────────────────────────────
test_ecs_resiliency() {
  step "ECS Resiliency Test — killing a Fargate task"

  # List running tasks
  TASKS=$(aws ecs list-tasks \
    --cluster "$CLUSTER" \
    --service-name shopnow-dev-frontend \
    --desired-status RUNNING \
    --region "$REGION" \
    --query 'taskArns' \
    --output text)

  if [[ -z "$TASKS" ]]; then
    warn "No running ECS tasks found. Is the cluster deployed?"
    return
  fi

  # Pick the first task
  TASK_ARN=$(echo "$TASKS" | awk '{print $1}')
  log "Target task: $TASK_ARN"

  # Count tasks before
  BEFORE=$(aws ecs list-tasks --cluster "$CLUSTER" \
    --service-name shopnow-dev-frontend \
    --desired-status RUNNING --region "$REGION" \
    --query 'length(taskArns)' --output text)
  log "Tasks before kill: $BEFORE"

  # Kill it
  log "Stopping task..."
  aws ecs stop-task --cluster "$CLUSTER" --task "$TASK_ARN" \
    --reason "Resiliency test" --region "$REGION" >/dev/null
  log "Task stopped."

  # Watch recovery
  log "Watching ECS recover (up to 3 minutes)..."
  for i in $(seq 1 18); do
    sleep 10
    COUNT=$(aws ecs list-tasks --cluster "$CLUSTER" \
      --service-name shopnow-dev-frontend \
      --desired-status RUNNING --region "$REGION" \
      --query 'length(taskArns)' --output text 2>/dev/null || echo "0")
    log "Attempt $i — Running tasks: $COUNT / $BEFORE"
    if [[ "$COUNT" -ge "$BEFORE" ]]; then
      log "✅ ECS RECOVERED: $COUNT tasks running (target: $BEFORE)"
      return
    fi
  done
  warn "❌ ECS did not fully recover within 3 minutes — check ECS console"
}

# ── EKS Resiliency Test ───────────────────────────────────────────────────────
test_eks_resiliency() {
  step "EKS Resiliency Test — killing a Kubernetes pod"

  # Get a frontend pod
  POD=$(kubectl get pods -n "$NAMESPACE" -l app=frontend \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [[ -z "$POD" ]]; then
    warn "No running frontend pods found. Is EKS deployed?"
    return
  fi

  log "Target pod: $POD"

  # Count pods before
  BEFORE=$(kubectl get pods -n "$NAMESPACE" -l app=frontend \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')
  log "Pods before kill: $BEFORE"

  # Kill it
  log "Deleting pod..."
  kubectl delete pod "$POD" -n "$NAMESPACE" --grace-period=0 --force
  log "Pod deleted."

  # Watch recovery
  log "Watching Kubernetes recover (up to 3 minutes)..."
  for i in $(seq 1 18); do
    sleep 10
    COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=frontend \
      --field-selector=status.phase=Running \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')
    log "Attempt $i — Running pods: $COUNT / $BEFORE"
    if [[ "$COUNT" -ge "$BEFORE" ]]; then
      log "✅ EKS RECOVERED: $COUNT pods running (target: $BEFORE)"
      return
    fi
  done
  warn "❌ EKS did not fully recover within 3 minutes — check kubectl describe pod"
}

# ── Run tests ─────────────────────────────────────────────────────────────────
echo ""
log "============= SHOPNOW RESILIENCY TEST ============="
echo ""

case "$TARGET" in
  ecs)  test_ecs_resiliency ;;
  eks)  test_eks_resiliency ;;
  both) test_ecs_resiliency; echo ""; test_eks_resiliency ;;
  *)    warn "Unknown target: $TARGET. Use: ecs | eks | both" ;;
esac

echo ""
log "============= TEST COMPLETE ============="
