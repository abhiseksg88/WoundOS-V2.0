"""Pub/Sub worker — subscribes to scan-jobs topic and processes scans.

This runs as a separate process (or Cloud Run service) that pulls
messages from the Pub/Sub subscription, downloads frames from GCS,
runs the pipeline orchestrator, and updates Firestore with results.
"""

import json
import logging
import signal
import sys
import time

from app.config import settings

logger = logging.getLogger("woundos.worker")

_running = True


def signal_handler(sig, frame):
    global _running
    logger.info("Received signal %s, shutting down gracefully...", sig)
    _running = False


def process_message(message) -> None:
    """Process a single Pub/Sub message."""
    from app.services import firestore, storage
    from pipeline.orchestrator import get_orchestrator

    data = json.loads(message.data.decode("utf-8"))
    job_id = data["job_id"]
    logger.info("Processing job %s", job_id)

    # Load job document
    job_doc = firestore.get_job(job_id)
    if job_doc is None:
        logger.error("Job %s not found in Firestore", job_id)
        message.ack()
        return

    try:
        # Download frames from GCS
        frames = storage.download_frames(job_id)
        if not frames:
            raise RuntimeError(f"No frames found in GCS for job {job_id}")

        # Run pipeline
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
        firestore.update_job_status(
            job_id,
            firestore.JobStatus.FAILED,
            error=str(e),
        )

    message.ack()


def run_worker():
    """Main worker loop — subscribe to Pub/Sub and process messages."""
    from app.services.pubsub import create_subscriber, subscription_path

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    logger.info("Worker starting (project=%s, subscription=%s)",
                settings.gcp_project_id, settings.pubsub_subscription)

    # Preload models
    logger.info("Preloading ML models...")
    from pipeline.orchestrator import get_orchestrator
    get_orchestrator()
    logger.info("Models loaded, starting message consumption...")

    subscriber = create_subscriber()
    sub_path = subscription_path()

    # Flow control: process 1 message at a time (GPU exclusive)
    from google.cloud.pubsub_v1.types import FlowControl
    flow_control = FlowControl(max_messages=1)

    streaming_pull_future = subscriber.subscribe(
        sub_path,
        callback=process_message,
        flow_control=flow_control,
    )

    logger.info("Worker listening for messages on %s", sub_path)

    try:
        while _running:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        streaming_pull_future.cancel()
        streaming_pull_future.result(timeout=10)
        subscriber.close()
        logger.info("Worker shut down.")


if __name__ == "__main__":
    run_worker()
