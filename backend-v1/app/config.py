"""Pydantic settings for WoundOS API. All env vars prefixed with WOUNDOS_."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables.

    All variables are prefixed with WOUNDOS_, e.g. WOUNDOS_API_TOKEN.
    """

    api_token: str = "dev-token-change-me"
    gcp_project: str = "careplix-woundos"
    gcs_bucket: str = "woundos-scans"
    firestore_collection: str = "wound_scans"
    pubsub_topic: str = "scan-validations"
    anthropic_api_key: str | None = None
    signed_url_expiry_minutes: int = 60

    model_config = {"env_prefix": "WOUNDOS_"}


def get_settings() -> Settings:
    """Return a cached Settings instance."""
    return Settings()
