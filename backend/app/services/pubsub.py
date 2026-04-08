"""Google Cloud Pub/Sub service for job queue."""

import json
import logging

from google.cloud import pubsub_v1

from app.config import settings

logger = logging.getLogger("woundos.pubsub")

_publisher: pubsub_v1.PublisherClient | None = None


def _get_publisher() -> pubsub_v1.PublisherClient:
    global _publisher
    if _publisher is None:
        _publisher = pubsub_v1.PublisherClient()
    return _publisher


def _topic_path() -> str:
    return _get_publisher().topic_path(settings.gcp_project_id, settings.pubsub_topic)


def publish_scan_job(job_id: str, tier: int = 1) -> None:
    """Publish a scan processing job to Pub/Sub."""
    publisher = _get_publisher()
    message = json.dumps({"job_id": job_id, "tier": tier}).encode("utf-8")
    future = publisher.publish(
        _topic_path(),
        data=message,
        job_id=job_id,
        tier=str(tier),
    )
    message_id = future.result()
    logger.info("Published job %s (tier %d), message_id=%s", job_id, tier, message_id)


def create_subscriber() -> pubsub_v1.SubscriberClient:
    """Create a Pub/Sub subscriber client."""
    return pubsub_v1.SubscriberClient()


def subscription_path() -> str:
    """Get the full subscription path."""
    subscriber = create_subscriber()
    return subscriber.subscription_path(settings.gcp_project_id, settings.pubsub_subscription)
