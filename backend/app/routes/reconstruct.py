"""POST /api/v2/reconstruct — Submit a wound scan for processing.
POST /process — Pub/Sub push endpoint for async job processing.
"""

import base64
import json
import logging
import uuid
import threading

from fastapi import APIRouter, File, Form, UploadFile, HTTPException, Request

from app.config import settings
from app.models.job import JobDocument, JobStatus, JobSubmitResponse
from app.services import firestore, storage, pubsub

logger = logging.getLogger("woundos.routes.reconstruct")

router = APIRouter()


@router.post("/api/v2/reconstruct", response_model=JobSubmitResponse, status_code=202)
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

    # If running in "all" mode (GPU worker), process directly in background thread
    if settings.worker_mode in ("gpu", "all"):
        _process_job_background(job_id)
    else:
        # Publish to Pub/Sub for separate worker pickup
        pubsub.publish_scan_job(job_id, tier=1)

    return JobSubmitResponse(jobId=job_id)


@router.post("/process")
async def pubsub_push_handler(request: Request):
    """Receive Pub/Sub push messages and process scan jobs.

    Pub/Sub sends messages as:
    {"message": {"data": "<base64-encoded JSON>", "messageId": "..."}, "subscription": "..."}
    """
    body = await request.json()
    message = body.get("message", {})
    data_b64 = message.get("data", "")

    try:
        data = json.loads(base64.b64decode(data_b64))
        job_id = data["job_id"]
    except (json.JSONDecodeError, KeyError) as e:
        logger.error("Invalid Pub/Sub message: %s", e)
        return {"status": "error", "detail": str(e)}

    logger.info("Pub/Sub push: processing job %s", job_id)
    _process_job_background(job_id)
    return {"status": "ok", "jobId": job_id}


def _process_job_background(job_id: str) -> None:
    """Process a job in a background thread so the HTTP response returns quickly."""

    def _run():
        try:
            job_doc = firestore.get_job(job_id)
            if job_doc is None:
                logger.error("Job %s not found in Firestore", job_id)
                return

            frames = storage.download_frames(job_id)
            if not frames:
                raise RuntimeError(f"No frames found in GCS for job {job_id}")

            from pipeline.orchestrator import get_orchestrator
            orchestrator = get_orchestrator()
            orchestrator.process_scan(
                job_id=job_id,
                frames=frames,
                poses=job_doc.poses or [],
                intrinsics=job_doc.intrinsics or {},
                wound_point=job_doc.wound_point,
                use_woundambit=job_doc.use_woundambit,
                generate_splat=job_doc.generate_splat,
            )
            logger.info("Job %s processed successfully", job_id)
        except Exception as e:
            logger.error("Job %s failed: %s", job_id, e, exc_info=True)
            firestore.update_job_status(job_id, JobStatus.FAILED, error=str(e))

    thread = threading.Thread(target=_run, daemon=True)
    thread.start()
