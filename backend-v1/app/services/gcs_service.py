"""Google Cloud Storage signed URL generation for wound scan binaries."""

from __future__ import annotations

import logging
from datetime import timedelta

from google.cloud import storage  # type: ignore[attr-defined]

from app.config import Settings

logger = logging.getLogger(__name__)

# Allowed file extensions for upload
ALLOWED_FILES = {"rgb.jpg", "depth.bin", "mesh.obj", "annotated.jpg", "mask.png"}


class GCSService:
    """Manages signed URL generation for the woundos-scans bucket."""

    def __init__(self, settings: Settings) -> None:
        self._client = storage.Client(project=settings.gcp_project)
        self._bucket_name = settings.gcs_bucket
        self._expiry_minutes = settings.signed_url_expiry_minutes

    def generate_upload_urls(
        self,
        scan_id: str,
        files: list[str],
    ) -> dict[str, str]:
        """Generate signed upload (PUT) URLs for the requested files.

        Args:
            scan_id: The scan UUID used as the GCS prefix.
            files: List of filenames (e.g. ["rgb.jpg", "depth.bin"]).

        Returns:
            Mapping of filename to signed URL string.

        Raises:
            ValueError: If a filename is not in the allowed set.
        """
        invalid = set(files) - ALLOWED_FILES
        if invalid:
            raise ValueError(f"Invalid file names: {invalid}. Allowed: {ALLOWED_FILES}")

        bucket = self._client.bucket(self._bucket_name)
        urls: dict[str, str] = {}

        for filename in files:
            blob = bucket.blob(f"{scan_id}/{filename}")

            # Determine content type
            content_type = _content_type_for(filename)

            url = blob.generate_signed_url(
                version="v4",
                expiration=timedelta(minutes=self._expiry_minutes),
                method="PUT",
                content_type=content_type,
            )
            urls[filename] = url
            logger.debug("Generated signed URL for %s/%s", scan_id, filename)

        return urls

    def download_blob_bytes(self, scan_id: str, filename: str) -> bytes:
        """Download a blob from GCS and return its contents as bytes."""
        bucket = self._client.bucket(self._bucket_name)
        blob = bucket.blob(f"{scan_id}/{filename}")
        return blob.download_as_bytes()


def _content_type_for(filename: str) -> str:
    """Return the MIME content type for a known upload filename."""
    ext = filename.rsplit(".", 1)[-1].lower()
    mapping = {
        "jpg": "image/jpeg",
        "png": "image/png",
        "bin": "application/octet-stream",
        "obj": "model/obj",
    }
    return mapping.get(ext, "application/octet-stream")
