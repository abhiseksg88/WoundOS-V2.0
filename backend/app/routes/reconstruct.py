"""POST /api/v2/reconstruct — Submit a wound scan for processing.
POST /process — Pub/Sub push endpoint for async job processing.

Supports two modes:
- mode=multiview (default): existing 30-frame Depth Pro + COLMAP MVS pipeline
- mode=lidar: new LiDAR-native pipeline using ARKit scene reconstruction mesh
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
    mesh: UploadFile | None = File(default=None, description="OBJ mesh from ARKit (LiDAR mode)"),
    depth: UploadFile | None = File(default=None, description="16-bit depth PNG (LiDAR mode, optional)"),
    mode: str = Form(default="multiview", description="'multiview' or 'lidar'"),
    wound_point: str = Form(default=None, description="Wound center point as 'x,y'"),
    use_woundambit: str = Form(default="false"),
    generate_splat: str = Form(default="false"),
    source_platform: str = Form(default=""),
    device_model: str = Form(default=""),
):
    """Accept a wound scan and queue it for processing.

    Returns a jobId immediately. Poll GET /api/v2/jobs/{jobId} for results.

    Two modes:
    - 'multiview' (default): expects 20-50 frames, uses Depth Pro + COLMAP MVS (30-60s)
    - 'lidar': expects 1 frame + 'mesh' OBJ file, uses ARKit native (3-5s)
    """
    mode = mode.lower().strip()
    if mode not in ("multiview", "lidar"):
        raise HTTPException(status_code=400, detail=f"Invalid mode: {mode}")

    if mode == "lidar" and not settings.enable_lidar_mode:
        raise HTTPException(status_code=400, detail="LiDAR mode is disabled on this server")

    # Validate frame count
    if len(frames) < 1:
        raise HTTPException(status_code=400, detail="At least one frame is required")

    if mode == "lidar" and mesh is None:
        raise HTTPException(status_code=400, detail="mesh field required when mode=lidar")

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

    # LiDAR mode requires exactly 1 frame
    if mode == "lidar" and len(frames) != 1:
        raise HTTPException(
            status_code=400,
            detail=f"LiDAR mode requires exactly 1 frame, got {len(frames)}"
        )

    # Generate job ID
    job_id = str(uuid.uuid4())
    logger.info("New %s reconstruction job %s: %d frames", mode, job_id, len(frames))

    # Read all frame data
    frame_bytes = []
    for f in frames:
        data = await f.read()
        frame_bytes.append(data)

    # Upload frames to GCS
    gcs_prefix = storage.upload_frames(job_id, frame_bytes)

    # LiDAR mode: upload mesh and optional depth PNG
    gcs_mesh_path = None
    gcs_depth_path = None
    if mode == "lidar":
        mesh_bytes = await mesh.read()
        if len(mesh_bytes) > settings.lidar_mesh_max_bytes:
            raise HTTPException(
                status_code=413,
                detail=f"Mesh file too large: {len(mesh_bytes)} > {settings.lidar_mesh_max_bytes} bytes"
            )
        gcs_mesh_path = storage.upload_mesh(job_id, mesh_bytes)

        if depth is not None:
            depth_bytes = await depth.read()
            gcs_depth_path = storage.upload_depth_png(job_id, depth_bytes)

    # Create job document in Firestore
    doc = JobDocument(
        job_id=job_id,
        status=JobStatus.QUEUED,
        mode=mode,
        frames_count=len(frames),
        gcs_frames_prefix=gcs_prefix,
        gcs_mesh_path=gcs_mesh_path,
        gcs_depth_path=gcs_depth_path,
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
        if mode == "lidar":
            _process_lidar_job_background(job_id)
        else:
            _process_job_background(job_id)
    else:
        # Publish to Pub/Sub for separate worker pickup
        pubsub.publish_scan_job(job_id, tier=1)

    estimated = 5 if mode == "lidar" else 60
    return JobSubmitResponse(jobId=job_id, estimatedDurationSeconds=estimated)


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

    # Look up the job to determine which pipeline to use
    job_doc = firestore.get_job(job_id)
    if job_doc and job_doc.mode == "lidar":
        _process_lidar_job_background(job_id)
    else:
        _process_job_background(job_id)
    return {"status": "ok", "jobId": job_id}


def _process_job_background(job_id: str) -> None:
    """Process a multiview job in a background thread."""

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


def _process_lidar_job_background(job_id: str) -> None:
    """Process a LiDAR-mode job in a background thread."""

    def _run():
        try:
            job_doc = firestore.get_job(job_id)
            if job_doc is None:
                logger.error("LiDAR job %s not found in Firestore", job_id)
                return

            if not job_doc.gcs_mesh_path:
                raise RuntimeError(f"LiDAR job {job_id} has no mesh path")

            frames = storage.download_frames(job_id)
            if not frames:
                raise RuntimeError(f"No frames found in GCS for LiDAR job {job_id}")

            mesh_bytes = storage.download_mesh(job_id)

            poses = job_doc.poses or []
            if not poses:
                raise RuntimeError(f"LiDAR job {job_id} has no pose")

            from pipeline.orchestrator import get_orchestrator
            orchestrator = get_orchestrator()
            orchestrator.process_lidar_scan(
                job_id=job_id,
                frame_bytes=frames[0],
                pose=poses[0],
                intrinsics=job_doc.intrinsics or {},
                mesh_obj_bytes=mesh_bytes,
                wound_point=job_doc.wound_point,
            )
            logger.info("LiDAR job %s processed successfully", job_id)
        except Exception as e:
            logger.error("LiDAR job %s failed: %s", job_id, e, exc_info=True)
            firestore.update_job_status(job_id, JobStatus.FAILED, error=str(e))

    thread = threading.Thread(target=_run, daemon=True)
    thread.start()
