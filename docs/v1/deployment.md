# WoundOS Pro v1 — Deployment Runbook

## 1. Infrastructure Cleanup (Before v1 Build)

### 1.1 Delete failing GPU worker

```bash
# Delete Cloud Run GPU service (europe-west1)
gcloud run services delete woundos-worker \
  --region=europe-west1 --quiet

# Verify deletion
gcloud run services list --region=europe-west1
# Should be empty or show only woundos-api
```

### 1.2 Clean up old container images

```bash
# List old worker images
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/careplix-woundos/woundos/worker

# Delete old worker images (save registry storage costs)
gcloud artifacts docker images delete \
  us-central1-docker.pkg.dev/careplix-woundos/woundos/worker \
  --delete-tags --quiet 2>/dev/null || echo "No worker images to delete"
```

### 1.3 Verify GCE VM is deleted

```bash
gcloud compute instances list --project=careplix-woundos
# Should show no GPU instances
```

### 1.4 Infrastructure to KEEP (reused in v1)

These are already set up and will be reused:

| Resource | Name | Region | Status |
|----------|------|--------|--------|
| GCS Bucket | woundos-scans | us-central1 | Keep |
| GCS Bucket | woundos-splats | us-central1 | Keep (future use) |
| Firestore Database | (default) | us-central1 | Keep |
| Pub/Sub Topic | scan-jobs | global | Rename to scan-validations |
| Artifact Registry | woundos | us-central1 | Keep |
| Cloud Run | woundos-api | us-central1 | Delete and replace |

### 1.5 Rename Pub/Sub topic

```bash
# Delete old topic and subscription
gcloud pubsub subscriptions delete scan-jobs-worker --quiet
gcloud pubsub topics delete scan-jobs --quiet

# Create new topic with proper naming
gcloud pubsub topics create scan-validations
gcloud pubsub subscriptions create scan-validations-worker \
  --topic=scan-validations \
  --ack-deadline=300
```

### 1.6 Delete old Cloud Run API (replace with v1)

```bash
gcloud run services delete woundos-api \
  --region=us-central1 --quiet
```

---

## 2. v1 Backend Deployment

### 2.1 Prerequisites

- GCP project: `careplix-woundos`
- Region: `us-central1`
- Artifact Registry: `woundos` (already exists)
- GCS bucket: `woundos-scans` (already exists)
- Firestore: `(default)` database (already exists)
- Pub/Sub: `scan-validations` topic (created in step 1.5)

### 2.2 Build and deploy API Gateway

```bash
cd backend-v1

# Build API image
gcloud builds submit \
  --tag us-central1-docker.pkg.dev/careplix-woundos/woundos/wound-api:latest \
  --region=us-central1 .

# Deploy API Gateway
gcloud run deploy woundos-wound-api \
  --image=us-central1-docker.pkg.dev/careplix-woundos/woundos/wound-api:latest \
  --region=us-central1 \
  --cpu=2 --memory=2Gi \
  --min-instances=1 --max-instances=10 \
  --concurrency=80 --port=8080 --timeout=60 \
  --set-env-vars="WOUNDOS_GCP_PROJECT_ID=careplix-woundos,WOUNDOS_GCS_BUCKET=woundos-scans,WOUNDOS_FIRESTORE_COLLECTION=wound_scans,WOUNDOS_PUBSUB_TOPIC=scan-validations" \
  --allow-unauthenticated --quiet

# Get API URL
API_URL=$(gcloud run services describe woundos-wound-api \
  --region=us-central1 --format='value(status.url)')
echo "API Gateway: ${API_URL}"

# Verify
curl -s ${API_URL}/api/wound/v1/health | python3 -m json.tool
```

### 2.3 Build and deploy Shadow Validation Worker

```bash
cd backend-v1

# Build worker image (uses Dockerfile.worker)
gcloud builds submit \
  --tag us-central1-docker.pkg.dev/careplix-woundos/woundos/shadow-worker:latest \
  --dockerfile Dockerfile.worker \
  --region=us-central1 .

# Deploy worker
gcloud run deploy woundos-shadow-worker \
  --image=us-central1-docker.pkg.dev/careplix-woundos/woundos/shadow-worker:latest \
  --region=us-central1 \
  --cpu=4 --memory=8Gi \
  --min-instances=0 --max-instances=5 \
  --concurrency=1 --port=8080 --timeout=300 \
  --set-env-vars="WOUNDOS_GCP_PROJECT_ID=careplix-woundos,WOUNDOS_GCS_BUCKET=woundos-scans,WOUNDOS_FIRESTORE_COLLECTION=wound_scans" \
  --no-allow-unauthenticated --quiet

# Get worker URL
WORKER_URL=$(gcloud run services describe woundos-shadow-worker \
  --region=us-central1 --format='value(status.url)')

# Create Pub/Sub push subscription to trigger worker
gcloud pubsub subscriptions create scan-validations-push \
  --topic=scan-validations \
  --push-endpoint="${WORKER_URL}/validate" \
  --ack-deadline=300 \
  --push-auth-service-account=$(gcloud config get-value account)
```

### 2.4 Verify deployment

```bash
# Health check
curl -s ${API_URL}/api/wound/v1/health

# Expected:
# {"status":"healthy","version":"1.0.0","service":"woundos-wound-api",...}
```

---

## 3. iOS App Configuration

### 3.1 Update ServerConfig.swift

Replace the base URL in `WoundOSV2/Utilities/ServerConfig.swift`:

```swift
struct ServerConfig {
    // v1 API endpoints
    static let baseURL = "https://woundos-wound-api-333499614175.us-central1.run.app"
    static let scanEndpoint = "/api/wound/v1/scans"
    static let clinicalSummaryEndpoint = "/api/wound/v1/clinical-summary"
    static let healthEndpoint = "/api/wound/v1/health"
}
```

### 3.2 Build iOS app

Requires: Mac with Xcode 15+, iPhone Pro connected via USB.

```bash
# On Mac
git clone https://github.com/abhiseksg88/WoundOS-V2.0.git
cd WoundOS-V2.0
git checkout feature/v1-lidar-ondevice
open WoundOSV2/WoundOSV2.xcodeproj
```

In Xcode:
1. Select team (Signing & Capabilities)
2. Select iPhone Pro device as target
3. Cmd+R to build and run

---

## 4. Cost Estimate

### v1 at 100 scans/day

| Service | Config | Monthly Cost |
|---------|--------|-------------|
| Cloud Run API (woundos-wound-api) | 2 CPU, 2 GB, min 1 instance | ~$15 |
| Cloud Run Worker (woundos-shadow-worker) | 4 CPU, 8 GB, scale-to-zero | ~$10 |
| GCS Storage | ~500 MB/day growth | ~$5 |
| Firestore | ~3000 reads + 3000 writes/month | ~$2 |
| Pub/Sub | ~3000 messages/month | <$1 |
| Artifact Registry | 2 images | ~$1 |
| **Total** | | **~$34/month** |

### Comparison to v0 cloud GPU approach

| | v0 (Cloud GPU) | v1 (On-device + CPU shadow) |
|---|---|---|
| Monthly cost @ 100/day | ~$515 | ~$34 |
| **Reduction** | — | **93% cheaper** |

---

## 5. Monitoring

### 5.1 Cloud Run metrics (built-in)

- Request count, latency, error rate
- Instance count, CPU utilization
- Available in Cloud Console > Cloud Run > Metrics

### 5.2 Custom alerts (set up after deploy)

```bash
# Alert on high error rate (>5% of requests return 5xx)
gcloud monitoring policies create \
  --display-name="WoundOS API Error Rate" \
  --condition-display-name="5xx rate > 5%" \
  --condition-filter='resource.type="cloud_run_revision" AND metric.type="run.googleapis.com/request_count" AND metric.labels.response_code_class="5xx"' \
  --notification-channels="" \
  --combiner="OR"
```

### 5.3 Log queries for debugging

```bash
# API errors
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=woundos-wound-api AND severity>=ERROR" \
  --project=careplix-woundos --limit=20

# Shadow worker errors
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=woundos-shadow-worker AND severity>=ERROR" \
  --project=careplix-woundos --limit=20
```

---

## 6. Rollback Plan

If v1 deployment has issues:

```bash
# List recent revisions
gcloud run revisions list --service=woundos-wound-api --region=us-central1

# Roll back to previous revision
gcloud run services update-traffic woundos-wound-api \
  --region=us-central1 \
  --to-revisions=PREVIOUS_REVISION_NAME=100
```

For complete rollback to v0 (cloud GPU approach):
- Old code is preserved in branch `claude/woundos-v2-backend-1pCic`
- Old tag `v0-cloud-archive` points to the last working commit
- Can redeploy from that branch if needed (requires GPU quota)
