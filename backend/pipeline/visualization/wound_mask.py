"""Wound mask visualization — binary mask as base64 JPEG."""

import base64

import cv2
import numpy as np


def generate_wound_mask_base64(mask: np.ndarray) -> str:
    """Encode a binary wound mask as base64 JPEG.

    Args:
        mask: (H, W) uint8 array where 255=wound, 0=background.

    Returns:
        Base64-encoded JPEG string.
    """
    _, buf = cv2.imencode(".jpg", mask, [cv2.IMWRITE_JPEG_QUALITY, 90])
    return base64.b64encode(buf.tobytes()).decode("utf-8")
