# WoundOS V2 Backend

Cloud-deployed wound analysis pipeline: 3D reconstruction, segmentation, clinical-grade measurements, and AI-generated clinical summaries.

## Architecture

```
iOS App → POST /api/v2/reconstruct → Cloud Run API → Pub/Sub → GPU Worker
                                                                    │
                                     GET /api/v2/jobs/{id} ← Firestore ←┘
```

### Tiered Processing
- **Tier 1 (5-8s)**: Depth Pro + TSDF fusion + SAM 2 → preliminary measurements
- **Tier 2 (30-60s)**: COLMAP MVS + Poisson → gold-standard measurements
- **Tier 3 (optional)**: Gaussian Splatting → photorealistic 3D viewer

### ML Models
| Model | Purpose | Size | Speed |
|-------|---------|------|-------|
| Apple Depth Pro | Metric depth estimation | ~1.5 GB | 0.3s/frame |
| SAM 2.1 Hiera-L | Wound segmentation | ~900 MB | 44+ FPS |
| COLMAP | Multi-view stereo | ~200 MB | 40-90s/scan |
| Claude Haiku | Clinical summaries | API call | ~1s |

## Quick Start

### Prerequisites
- Python 3.11+
- GCP project with Firestore, Pub/Sub, Cloud Storage
- NVIDIA GPU (for ML inference) or use API-only mode

### Local Development (API only, no GPU)

```bash
cd backend
pip install -r requirements.txt
cp .env.example .env  # Edit with your GCP credentials

# Run API gateway
WOUNDOS_WORKER_MODE=api python -m uvicorn app.main:app --port 8080 --reload

# Test
curl http://localhost:8080/health
```

### Docker

```bash
# API gateway only
docker-compose up

# With GPU worker
docker-compose --profile gpu up
```

### Run Tests

```bash
pip install -r requirements.txt
pytest tests/ -v
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| POST | `/api/v2/reconstruct` | Submit wound scan → returns `{jobId}` |
| GET | `/api/v2/jobs/{jobId}` | Poll for processing results |
| POST | `/api/v1/segment` | Single-image segmentation → PNG mask |
| POST | `/api/v1/woundambit` | Wound contour extraction → JSON |

### Submit Scan
```bash
curl -X POST http://localhost:8080/api/v2/reconstruct \
  -F "frames=@frame_0.jpg" \
  -F "frames=@frame_1.jpg" \
  -F "poses=@poses.json" \
  -F "intrinsics=@intrinsics.json" \
  -F "wound_point=0.5,0.5" \
  -F "generate_splat=false"
# → {"jobId": "abc-123", "status": "queued", "estimatedDurationSeconds": 60}
```

### Poll Results
```bash
curl http://localhost:8080/api/v2/jobs/abc-123
# → {"jobId": "abc-123", "status": "tier1_complete", "result": {...}}
```

## GCP Deployment

### First-time setup
```bash
# Set your project
export GCP_PROJECT_ID=wound-ai-api

# Create resources
bash scripts/setup_gcp.sh
```

### Deploy
```bash
export ANTHROPIC_API_KEY=sk-ant-xxxxx
bash scripts/deploy_cloudrun.sh
```

### Infrastructure
| Component | Config | Cost (idle) |
|-----------|--------|-------------|
| API Gateway | Cloud Run, 4 vCPU, 8GB, no GPU | ~$50/mo |
| GPU Worker | Cloud Run, 8 vCPU, 32GB, 1x L4 | ~$550/mo |
| Storage | GCS bucket | ~$5/mo |
| Firestore | Native mode | ~$5/mo |

## Project Structure

```
backend/
├── app/              # FastAPI application
│   ├── routes/       # API endpoints
│   ├── models/       # Pydantic schemas
│   └── services/     # GCS, Firestore, Pub/Sub
├── pipeline/         # ML processing
│   ├── depth/        # Depth Pro
│   ├── segmentation/ # SAM 2 + tissue classification
│   ├── reconstruction/ # TSDF + COLMAP
│   ├── measurement/  # Area, depth, volume, L×W, PUSH
│   ├── visualization/ # Annotated images, heatmaps
│   └── clinical/     # Claude API summaries
├── worker/           # Pub/Sub subscriber
├── scripts/          # Deployment scripts
└── tests/            # Unit + integration tests
```
