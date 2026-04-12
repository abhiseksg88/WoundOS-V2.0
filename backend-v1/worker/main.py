"""Shadow Validation Worker — receives Pub/Sub push messages and runs SAM 2."""

from __future__ import annotations

import base64
import json
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from io import BytesIO
from typing import Any, AsyncIterator

import numpy as np
from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from google.cloud import firestore as firestore_mod  # type: ignore[attr-defined]
from google.cloud import storage as storage_mod  # type: ignore[attr-defined]
from PIL import Image

from worker.agreement_metrics import compute_agreement_metrics
from worker.sam2_inference import SAM2Predictor

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration (worker uses a subset of env vars)
# ---------------------------------------------------------------------------

import os

GCP_PROJECT = os.environ.get("WOUNDOS_GCP_PROJECT", "careplix-woundos")
GCS_BUCKET = os.environ.get("WOUNDOS_GCS_BUCKET", "woundos-scans")
FIRESTORE_COLLECTION = os.environ.get("WOUNDOS_FIRESTORE_COLLECTION", "wound_scans")

# ---------------------------------------------------------------------------
# Globals (initialized at startup)
# ---------------------------------------------------------------------------

_predictor: SAM2Predictor | None = None
_firestore_client: firestore_mod.Client | None = None
_storage_client: storage_mod.Client | None = None


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Load SAM 2 model on startup to avoid cold-start latency per request."""
    global _predictor, _firestore_client, _storage_client

    logger.info("Worker starting — loading SAM 2 model...")
    _predictor = SAM2Predictor()
    logger.info("SAM 2 model loaded")

    _firestore_client = firestore_mod.Client(project=GCP_PROJECT)
    _storage_client = storage_mod.Client(project=GCP_PROJECT)

    yield

    logger.info("Worker shutting down")


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

app = FastAPI(
    title="WoundOS Shadow Validation Worker",
    version="1.0.0",
    lifespan=lifespan,
)


@app.get("/health")
async def health() -> dict[str, str]:
    """Simple health check for the worker."""
    return {"status": "ok", "service": "woundos-validator-v1"}


@app.post("/pubsub/push")
async def pubsub_push(request: Request) -> JSONResponse:
    """Handle Pub/Sub push delivery.

    The Pub/Sub push wrapper sends a JSON envelope:
    {
        "message": {
            "data": "<base64-encoded JSON>",
            "messageId": "...",
            ...
        },
        "subscription": "..."
    }
    """
    try:
        envelope = await request.json()
        message = envelope.get("message", {})
        data_b64 = message.get("data", "")

        if not data_b64:
            logger.warning("Empty Pub/Sub message received")
            return JSONResponse(status_code=status.HTTP_200_OK, content={"status": "ignored"})

        payload = json.loads(base64.b64decode(data_b64))
        scan_id = payload.get("scan_id")

        if not scan_id:
            logger.warning("Pub/Sub message missing scan_id: %s", payload)
            return JSONResponse(status_code=status.HTTP_200_OK, content={"status": "ignored"})

        logger.info("Processing validation for scan %s", scan_id)
        await _process_scan(scan_id)

        return JSONResponse(status_code=status.HTTP_200_OK, content={"status": "ok"})

    except Exception:
        logger.exception("Failed to process Pub/Sub message")
        # Return 500 so Pub/Sub retries delivery
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"status": "error"},
        )


# ---------------------------------------------------------------------------
# Core processing
# ---------------------------------------------------------------------------


async def _process_scan(scan_id: str) -> None:
    """Download RGB, run SAM 2, compute metrics, store results."""
    assert _firestore_client is not None
    assert _storage_client is not None
    assert _predictor is not None

    col = _firestore_client.collection(FIRESTORE_COLLECTION)
    doc_ref = col.document(scan_id)

    # 1. Read scan document
    snap = doc_ref.get()
    if not snap.exists:
        logger.error("Scan %s not found in Firestore", scan_id)
        return

    scan = snap.to_dict()
    assert scan is not None

    # Update status
    doc_ref.update({"status": "validating", "updated_at": datetime.now(timezone.utc).isoformat()})

    try:
        # 2. Extract nurse data
        nurse_boundary = scan["nurse_boundary"]
        tap_center = nurse_boundary["tap_center_2d"]
        boundary_2d = nurse_boundary["boundary_2d"]
        image_width = scan["capture_metadata"]["image_width"]
        image_height = scan["capture_metadata"]["image_height"]

        # 3. Download RGB from GCS
        bucket = _storage_client.bucket(GCS_BUCKET)
        blob = bucket.blob(f"{scan_id}/rgb.jpg")

        max_retries = 3
        image_bytes = None
        for attempt in range(max_retries):
            try:
                image_bytes = blob.download_as_bytes()
                break
            except Exception:
                if attempt == max_retries - 1:
                    raise
                logger.warning("GCS download attempt %d failed for scan %s", attempt + 1, scan_id)

        assert image_bytes is not None
        image = Image.open(BytesIO(image_bytes)).convert("RGB")
        image_np = np.array(image)

        # 4. Run SAM 2 inference
        sam2_mask = _predictor.predict(
            image=image_np,
            point_coords=[[tap_center[0], tap_center[1]]],
            point_labels=[1],  # foreground
        )

        # 5. Create nurse boundary mask
        nurse_mask = _boundary_to_mask(boundary_2d, image_height, image_width)

        # 6. Compute agreement metrics
        metrics = compute_agreement_metrics(nurse_mask, sam2_mask)

        # 7. Store validation results
        validation_result: dict[str, Any] = {
            "sam2_model": "facebook/sam2.1-hiera-tiny",
            "iou": float(metrics["iou"]),
            "dice": float(metrics["dice"]),
            "area_delta_percent": float(metrics["area_delta_percent"]),
            "centroid_displacement_px": float(metrics["centroid_displacement_px"]),
            "validated_at": datetime.now(timezone.utc).isoformat(),
        }

        doc_ref.update({
            "validation": validation_result,
            "status": "validated",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        })

        logger.info(
            "Scan %s validated: IoU=%.3f, Dice=%.3f, area_delta=%.1f%%",
            scan_id,
            metrics["iou"],
            metrics["dice"],
            metrics["area_delta_percent"],
        )

    except Exception as exc:
        logger.exception("Validation failed for scan %s", scan_id)
        doc_ref.update({
            "status": "validation_failed",
            "validation_error": str(exc),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        })


def _boundary_to_mask(
    boundary_2d: list[list[float]],
    height: int,
    width: int,
) -> np.ndarray:
    """Convert a 2D boundary polygon to a filled binary mask.

    Args:
        boundary_2d: List of [x, y] pixel coordinates forming a polygon.
        height: Image height in pixels.
        width: Image width in pixels.

    Returns:
        Binary mask as uint8 numpy array of shape (height, width).
    """
    import cv2

    mask = np.zeros((height, width), dtype=np.uint8)
    if len(boundary_2d) < 3:
        return mask

    pts = np.array(boundary_2d, dtype=np.int32).reshape((-1, 1, 2))
    cv2.fillPoly(mask, [pts], color=1)
    return mask
