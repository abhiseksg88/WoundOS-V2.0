#!/usr/bin/env bash
# Deploy WoundOS V2 Backend to GCP Cloud Run
# Deploys both API gateway (CPU) and GPU worker

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-wound-ai-api}"
PROJECT_NUMBER="${GCP_PROJECT_NUMBER:-333499614175}"
REGION="${GCP_REGION:-us-central1}"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/woundos"

echo "=== WoundOS V2 Cloud Run Deployment ==="
echo "Project: ${PROJECT_ID} (${PROJECT_NUMBER})"
echo "Region:  ${REGION}"
echo ""

# Create Artifact Registry repository if needed
echo "Setting up Artifact Registry..."
gcloud artifacts repositories create woundos \
    --repository-format=docker \
    --location="${REGION}" \
    --project="${PROJECT_ID}" 2>/dev/null || echo "Repository already exists"

# Configure Docker auth
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# ─── Build and deploy API Gateway ───────────────────────────

echo ""
echo "=== Building API Gateway ==="
docker build -f Dockerfile.api -t "${REGISTRY}/api:latest" .
docker push "${REGISTRY}/api:latest"

echo "Deploying API Gateway to Cloud Run..."
gcloud run deploy woundos-api \
    --image="${REGISTRY}/api:latest" \
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

# Get API URL
API_URL=$(gcloud run services describe woundos-api --region="${REGION}" --project="${PROJECT_ID}" --format='value(status.url)')
echo "API Gateway URL: ${API_URL}"

# ─── Build and deploy GPU Worker ────────────────────────────

echo ""
echo "=== Building GPU Worker ==="
docker build -f Dockerfile -t "${REGISTRY}/worker:latest" .
docker push "${REGISTRY}/worker:latest"

echo "Deploying GPU Worker to Cloud Run..."
gcloud run deploy woundos-worker \
    --image="${REGISTRY}/worker:latest" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --platform=managed \
    --memory=32Gi \
    --cpu=8 \
    --gpu=1 \
    --gpu-type=nvidia-l4 \
    --min-instances=1 \
    --max-instances=5 \
    --concurrency=1 \
    --port=8080 \
    --timeout=300 \
    --no-cpu-throttling \
    --set-env-vars="WOUNDOS_WORKER_MODE=gpu,WOUNDOS_GCP_PROJECT_ID=${PROJECT_ID},WOUNDOS_ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}" \
    --command="python3,-m,worker.main" \
    --no-allow-unauthenticated

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "API Gateway: ${API_URL}"
echo ""
echo "Test with:"
echo "  curl ${API_URL}/health"
