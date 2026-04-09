"""Application configuration via environment variables."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # GCP
    gcp_project_id: str = "careplix-woundos"
    gcp_project_number: str = "333499614175"
    gcp_region: str = "us-central1"

    # Cloud Storage
    gcs_bucket: str = "woundos-scans"
    gcs_splat_bucket: str = "woundos-splats"
    gcs_signed_url_expiry_days: int = 30

    # Firestore
    firestore_collection: str = "jobs"

    # Pub/Sub
    pubsub_topic: str = "scan-jobs"
    pubsub_subscription: str = "scan-jobs-worker"

    # Worker
    worker_mode: str = "all"  # "api", "gpu", "all"

    # ML Models
    depth_pro_model_path: str = "/models/depth_pro"
    sam2_model_path: str = "/models/sam2"
    sam2_config: str = "sam2.1_hiera_l.yaml"
    sam2_checkpoint: str = "sam2.1_hiera_large.pt"

    # Claude API
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-haiku-4-5-20251001"

    # COLMAP
    colmap_binary: str = "colmap"
    colmap_max_image_size: int = 1600
    colmap_num_iterations: int = 5
    colmap_gpu_index: int = 0

    # Processing
    max_frames: int = 50
    min_frames: int = 20
    target_frames: int = 30
    tsdf_voxel_length: float = 0.0005  # 0.5mm
    tsdf_sdf_trunc: float = 0.004  # 4mm

    # Server
    host: str = "0.0.0.0"
    port: int = 8080
    cors_origins: list[str] = ["*"]
    api_version: str = "2.0.0"

    model_config = {"env_prefix": "WOUNDOS_", "env_file": ".env"}


settings = Settings()
