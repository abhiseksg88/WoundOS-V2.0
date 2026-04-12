"""Firestore CRUD operations for wound scan documents."""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from google.cloud import firestore  # type: ignore[attr-defined]

from app.config import Settings

logger = logging.getLogger(__name__)


class FirestoreService:
    """Manages wound_scans collection in Firestore."""

    def __init__(self, settings: Settings) -> None:
        self._client = firestore.Client(project=settings.gcp_project)
        self._collection = settings.firestore_collection

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _col(self) -> firestore.CollectionReference:
        return self._client.collection(self._collection)

    # ------------------------------------------------------------------
    # Create
    # ------------------------------------------------------------------

    def create_scan(self, data: dict[str, Any]) -> dict[str, Any]:
        """Insert a new scan document. Returns the document dict including scan_id."""
        scan_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()

        doc: dict[str, Any] = {
            "scan_id": scan_id,
            "status": "created",
            "created_at": now,
            "updated_at": now,
            **data,
        }

        self._col().document(scan_id).set(doc)
        logger.info("Created scan %s", scan_id)
        return doc

    # ------------------------------------------------------------------
    # Read
    # ------------------------------------------------------------------

    def get_scan(self, scan_id: str) -> dict[str, Any] | None:
        """Return a scan document by ID, or None if not found."""
        snap = self._col().document(scan_id).get()
        if not snap.exists:
            return None
        return snap.to_dict()

    def list_patient_scans(
        self,
        patient_id: str,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[list[dict[str, Any]], int]:
        """Return scans for a patient, ordered by created_at desc.

        Returns (scans_page, total_count).
        """
        base_query = self._col().where("patient_id", "==", patient_id)

        # Total count (Firestore does not have a native count prior to
        # the aggregation API; use it if available, else iterate).
        try:
            count_result = base_query.count().get()
            total = count_result[0][0].value  # type: ignore[index]
        except Exception:
            # Fallback: stream all IDs (acceptable at v1 scale).
            total = sum(1 for _ in base_query.select([]).stream())

        scans_query = (
            base_query
            .order_by("created_at", direction=firestore.Query.DESCENDING)
            .offset(offset)
            .limit(limit)
        )

        scans = [snap.to_dict() for snap in scans_query.stream()]
        return scans, total

    # ------------------------------------------------------------------
    # Update
    # ------------------------------------------------------------------

    def update_scan(self, scan_id: str, updates: dict[str, Any]) -> None:
        """Merge updates into an existing scan document."""
        updates["updated_at"] = datetime.now(timezone.utc).isoformat()
        self._col().document(scan_id).update(updates)
        logger.info("Updated scan %s: keys=%s", scan_id, list(updates.keys()))
