"""POST /api/v1/segment — Standalone wound segmentation endpoint."""

import io
import logging

import numpy as np
from fastapi import APIRouter, File, UploadFile, HTTPException
from fastapi.responses import Response
from PIL import Image

logger = logging.getLogger("woundos.routes.segment")

router = APIRouter(prefix="/api/v1")


@router.post("/segment", response_class=Response)
async def segment_wound(
    image: UploadFile = File(..., description="Single JPEG wound image"),
):
    """Segment a wound from a single image.

    Returns a binary PNG mask (white=wound, black=background).
    """
    image_data = await image.read()

    try:
        pil_image = Image.open(io.BytesIO(image_data)).convert("RGB")
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid image file")

    img_array = np.array(pil_image)

    # Run SAM 2 segmentation
    from pipeline.segmentation.sam2 import get_sam2_segmenter
    segmenter = get_sam2_segmenter()
    mask = segmenter.segment(img_array)

    # Encode mask as PNG
    mask_image = Image.fromarray(mask)
    buf = io.BytesIO()
    mask_image.save(buf, format="PNG")
    buf.seek(0)

    return Response(
        content=buf.getvalue(),
        media_type="image/png",
    )
