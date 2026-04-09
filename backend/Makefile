.PHONY: help run test build deploy setup-gcp lint

PYTHON ?= python3
PROJECT_ID ?= wound-ai-api
REGION ?= us-central1

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ─── Local Development ───────────────────────────────────────

run: ## Run API locally (no GPU, API mode only)
	WOUNDOS_WORKER_MODE=api $(PYTHON) -m uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload

run-all: ## Run API + worker locally (requires GPU)
	WOUNDOS_WORKER_MODE=all $(PYTHON) -m uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload

test: ## Run tests
	$(PYTHON) -m pytest tests/ -v --tb=short

lint: ## Run linting
	$(PYTHON) -m ruff check .

# ─── Docker ──────────────────────────────────────────────────

build-api: ## Build API gateway Docker image
	docker build -f Dockerfile.api -t woundos-api .

build-worker: ## Build GPU worker Docker image
	docker build -f Dockerfile -t woundos-worker .

docker-up: ## Start local Docker stack (API only)
	docker-compose up -d

docker-up-gpu: ## Start local Docker stack with GPU worker
	docker-compose --profile gpu up -d

docker-down: ## Stop Docker stack
	docker-compose --profile gpu down

# ─── GCP Deployment ─────���────────────────────────────────────

setup-gcp: ## Create GCP resources (bucket, Pub/Sub, Firestore)
	bash scripts/setup_gcp.sh

deploy: ## Deploy to Cloud Run
	bash scripts/deploy_cloudrun.sh

deploy-api: ## Deploy API gateway only
	gcloud run deploy woundos-api \
		--source . \
		--dockerfile Dockerfile.api \
		--region $(REGION) \
		--project $(PROJECT_ID) \
		--memory 8Gi \
		--cpu 4 \
		--min-instances 1 \
		--max-instances 20 \
		--concurrency 80 \
		--port 8080 \
		--set-env-vars="WOUNDOS_WORKER_MODE=api" \
		--allow-unauthenticated

deploy-worker: ## Deploy GPU worker
	gcloud run deploy woundos-worker \
		--source . \
		--dockerfile Dockerfile \
		--region $(REGION) \
		--project $(PROJECT_ID) \
		--memory 32Gi \
		--cpu 8 \
		--gpu 1 \
		--gpu-type nvidia-l4 \
		--min-instances 1 \
		--max-instances 5 \
		--concurrency 1 \
		--timeout 300 \
		--no-cpu-throttling \
		--set-env-vars="WOUNDOS_WORKER_MODE=gpu" \
		--command="python3,-m,worker.main"
