#!/usr/bin/env bash
# Deploy WoundOS V2 API Gateway to Cloud Run (CPU-only)
#
# The API Gateway handles:
# - Frame uploads (POST /api/v2/reconstruct)
# - Job polling (GET /api/v2/jobs/{id})
# - Segmentation proxy (POST /api/v1/segment)
# - Health checks (GET /health)
#
# The GPU Worker runs separately on GCE VM — see deploy_gce_worker.sh
#
# Usage:
#   bash scripts/deploy_cloudrun.sh

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-careplix-woundos}"
REGION="${GCP_REGION:-us-central1}"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/woundos"
API_IMAGE="${REGISTRY}/api:latest"

echo "============================================"
echo "  WoundOS V2 — API Gateway Deployment"
echo "============================================"
echo "Project: ${PROJECT_ID}"
echo "Region:  ${REGION}"
echo "Image:   ${API_IMAGE}"
echo ""

# ─── Step 1: Build API Gateway Image ─────────────────────────

echo "=== Step 1: Building API Gateway Image ==="

gcloud builds submit \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --config=cloudbuild-api.yaml \
    --substitutions="_IMAGE_TAG=${API_IMAGE}" \
    .

echo ""
echo "✓ API image built and pushed to ${API_IMAGE}"
echo ""

# ─── Step 2: Deploy to Cloud Run ─────────────────────────────

echo "=== Step 2: Deploying to Cloud Run ==="

gcloud run deploy woundos-api \
    --image="${API_IMAGE}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --platform=managed \
    --memory=8Gi \
    --cpu=4 \
    --min-instances=1 \
    --max-instances=20 \
    --concurrency=80 \
    --port=8080 \
    --timeout=60 \
    --set-env-vars="WOUNDOS_WORKER_MODE=api,WOUNDOS_GCP_PROJECT_ID=${PROJECT_ID}" \
    --allow-unauthenticated

# ─── Done ─────────────────────────────────────────────────────

API_URL=$(gcloud run services describe woundos-api \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --format='value(status.url)')

echo ""
echo "============================================"
echo "  API Gateway Deployment Complete"
echo "============================================"
echo ""
echo "URL: ${API_URL}"
echo ""
echo "Test:"
echo "  curl ${API_URL}/health"
echo ""
echo "Next: Deploy GPU Worker on GCE VM:"
echo "  export ANTHROPIC_API_KEY=sk-ant-xxx"
echo "  bash scripts/deploy_gce_worker.sh"
echo ""
