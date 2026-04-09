#!/usr/bin/env bash
# Setup GCP resources for WoundOS V2 Backend
# Run once before first deployment

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-wound-ai-api}"
REGION="${GCP_REGION:-us-central1}"

echo "=== WoundOS V2 GCP Setup ==="
echo "Project: ${PROJECT_ID}"
echo "Region:  ${REGION}"
echo ""

# Enable required APIs
echo "Enabling GCP APIs..."
gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    storage.googleapis.com \
    firestore.googleapis.com \
    pubsub.googleapis.com \
    --project="${PROJECT_ID}"

# Create Cloud Storage buckets
echo "Creating GCS buckets..."
gsutil mb -p "${PROJECT_ID}" -l "${REGION}" "gs://woundos-scans" 2>/dev/null || echo "Bucket woundos-scans already exists"
gsutil mb -p "${PROJECT_ID}" -l "${REGION}" "gs://woundos-splats" 2>/dev/null || echo "Bucket woundos-splats already exists"

# Set lifecycle policy (auto-delete frames after 30 days)
cat > /tmp/lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 30, "matchesPrefix": ["frames/"]}
    }
  ]
}
EOF
gsutil lifecycle set /tmp/lifecycle.json "gs://woundos-scans"
rm /tmp/lifecycle.json

# Create Firestore database (Native mode)
echo "Setting up Firestore..."
gcloud firestore databases create \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --type=firestore-native 2>/dev/null || echo "Firestore database already exists"

# Create Pub/Sub topic and subscription
echo "Creating Pub/Sub resources..."
gcloud pubsub topics create scan-jobs \
    --project="${PROJECT_ID}" 2>/dev/null || echo "Topic scan-jobs already exists"

gcloud pubsub subscriptions create scan-jobs-worker \
    --project="${PROJECT_ID}" \
    --topic=scan-jobs \
    --ack-deadline=300 \
    --message-retention-duration=1h \
    --max-delivery-attempts=3 2>/dev/null || echo "Subscription scan-jobs-worker already exists"

echo ""
echo "=== GCP Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Set ANTHROPIC_API_KEY in your environment or .env file"
echo "  2. Run: make deploy"
