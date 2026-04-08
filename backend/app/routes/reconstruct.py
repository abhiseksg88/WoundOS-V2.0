"""POST /api/v2/reconstruct — Submit a wound scan for processing."""

import json
import logging
import uuid

from fastapi import APIRouter, File, Form, UploadFile, HTTPException

from app.models.job import JobDocument, JobStatus, JobSubmitResponse
from app.services import firestore, storage, pubsub

logger = logging.getLogger("woundos.routes.reconstruct")

router = APIRouter(prefix="/api/v2")


@router.post("/reconstruct", response_model=JobSubmitResponse, status_code=202)
async def submit_reconstruction(
    frames: list[UploadFile] = File(..., description="JPEG frames from ARKit capture"),
    poses: UploadFile = File(..., description="JSON file with camera poses array"),
    intrinsics: UploadFile = File(..., description="JSON file with camera intrinsics"),
    wound_point: str = Form(default=None, description="Wound center point as 'x,y'"),
    use_woundambit: str = Form(default="false"),
    generate_splat: str = Form(default="false"),
    source_platform: str = Form(default=""),
    device_model: str = Form(default=""),
):
    """Accept a multi-frame wound scan and queue it for processing.

    Returns a jobId immediately. Poll GET /api/v2/jobs/{jobId} for results.
    """
    # Validate frame count
    if len(frames) < 1:
        raise HTTPException(status_code=400, detail="At least one frame is required")

    # Parse poses JSON
    poses_data = await poses.read()
    try:
        poses_list = json.loads(poses_data)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid poses JSON")

    # Parse intrinsics JSON
    intrinsics_data = await intrinsics.read()
    try:
        intrinsics_dict = json.loads(intrinsics_data)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid intrinsics JSON")

    # Validate pose count matches frame count
    if len(poses_list) != len(frames):
        raise HTTPException(
            status_code=400,
            detail=f"Frame count ({len(frames)}) does not match pose count ({len(poses_list)})",
        )

    # Generate job ID
    job_id = str(uuid.uuid4())
    logger.info("New reconstruction job %s: %d frames", job_id, len(frames))

    # Read all frame data
    frame_bytes = []
    for f in frames:
        data = await f.read()
        frame_bytes.append(data)

    # Upload frames to GCS
    gcs_prefix = storage.upload_frames(job_id, frame_bytes)

    # Create job document in Firestore
    doc = JobDocument(
        job_id=job_id,
        status=JobStatus.QUEUED,
        frames_count=len(frames),
        gcs_frames_prefix=gcs_prefix,
        wound_point=wound_point,
        use_woundambit=use_woundambit.lower() == "true",
        generate_splat=generate_splat.lower() == "true",
        source_platform=source_platform,
        device_model=device_model,
        intrinsics=intrinsics_dict,
        poses=poses_list,
    )
    firestore.create_job(doc)

    # Publish to Pub/Sub for worker pickup
    pubsub.publish_scan_job(job_id, tier=1)

    return JobSubmitResponse(jobId=job_id)
