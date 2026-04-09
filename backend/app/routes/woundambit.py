"""POST /api/v1/woundambit — Wound contour extraction endpoint."""

import io
import logging

import cv2
import numpy as np
from fastapi import APIRouter, File, UploadFile, HTTPException
from PIL import Image

logger = logging.getLogger("woundos.routes.woundambit")

router = APIRouter(prefix="/api/v1")


@router.post("/woundambit")
async def extract_wound_contour(
    image: UploadFile = File(..., description="Single JPEG wound image"),
):
    """Extract wound boundary contour from a single image.

    Uses SAM 2 segmentation + contour extraction to produce an ordered
    list of boundary points suitable for WoundAmbit visualization.
    """
    image_data = await image.read()

    try:
        pil_image = Image.open(io.BytesIO(image_data)).convert("RGB")
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid image file")

    img_array = np.array(pil_image)

    # Run segmentation
    from pipeline.segmentation.sam2 import get_sam2_segmenter
    segmenter = get_sam2_segmenter()
    mask = segmenter.segment(img_array)

    # Extract contours from mask
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if not contours:
        return {"contours": [], "area_pixels": 0}

    # Take the largest contour
    largest = max(contours, key=cv2.contourArea)
    area_pixels = cv2.contourArea(largest)
    perimeter_pixels = cv2.arcLength(largest, closed=True)

    # Simplify contour (Ramer-Douglas-Peucker)
    epsilon = 0.005 * perimeter_pixels
    simplified = cv2.approxPolyDP(largest, epsilon, closed=True)

    # Convert to list of [x, y] points
    points = simplified.reshape(-1, 2).tolist()

    return {
        "contours": [points],
        "area_pixels": float(area_pixels),
        "perimeter_pixels": float(perimeter_pixels),
        "num_points": len(points),
        "image_width": img_array.shape[1],
        "image_height": img_array.shape[0],
    }
