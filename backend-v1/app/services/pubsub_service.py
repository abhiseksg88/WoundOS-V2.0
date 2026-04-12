"""Pub/Sub publisher for triggering the shadow validation worker."""

from __future__ import annotations

import json
import logging

from google.cloud import pubsub_v1  # type: ignore[attr-defined]

from app.config import Settings

logger = logging.getLogger(__name__)


class PubSubService:
    """Publishes messages to the scan-validations Pub/Sub topic."""

    def __init__(self, settings: Settings) -> None:
        self._publisher = pubsub_v1.PublisherClient()
        self._topic_path = self._publisher.topic_path(
            settings.gcp_project, settings.pubsub_topic
        )

    def publish_scan_validation(self, scan_id: str) -> str:
        """Publish a validation request for the given scan.

        Args:
            scan_id: UUID of the scan to validate.

        Returns:
            The Pub/Sub message ID.
        """
        payload = json.dumps({"scan_id": scan_id}).encode("utf-8")
        future = self._publisher.publish(self._topic_path, data=payload)
        message_id = future.result()
        logger.info(
            "Published scan-validation message for %s (msg_id=%s)",
            scan_id,
            message_id,
        )
        return message_id
