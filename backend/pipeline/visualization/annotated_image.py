"""Generate annotated wound image with boundary, dimension lines, and depth marker."""

import base64
import io

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def generate_annotated_image(
    frame: np.ndarray,
    wound_contour: np.ndarray,
    length_mm: float,
    width_mm: float,
    length_endpoints: tuple[np.ndarray, np.ndarray] | None = None,
    width_endpoints: tuple[np.ndarray, np.ndarray] | None = None,
    deepest_point_px: tuple[int, int] | None = None,
    max_depth_mm: float = 0.0,
) -> str:
    """Draw wound boundary, dimension lines, and depth marker on a frame.

    Args:
        frame: (H, W, 3) RGB image.
        wound_contour: (N, 2) array of contour points in pixel coordinates.
        length_mm: Greatest length measurement.
        width_mm: Greatest width measurement.
        length_endpoints: Optional (start, end) pixel coordinates for length line.
        width_endpoints: Optional (start, end) pixel coordinates for width line.
        deepest_point_px: Optional (x, y) pixel coordinates of deepest point.
        max_depth_mm: Maximum depth value for label.

    Returns:
        Base64-encoded JPEG string.
    """
    img = frame.copy()
    h, w = img.shape[:2]

    # Draw wound boundary contour (green, 2px)
    if len(wound_contour) > 0:
        contour_int = wound_contour.astype(np.int32).reshape(-1, 1, 2)
        cv2.drawContours(img, [contour_int], -1, (0, 255, 0), 2)

        # Semi-transparent wound fill (green, 20% opacity)
        overlay = img.copy()
        cv2.fillPoly(overlay, [contour_int], (0, 255, 0))
        cv2.addWeighted(overlay, 0.2, img, 0.8, 0, img)

    # Draw length line (yellow)
    if length_endpoints is not None:
        p1 = tuple(length_endpoints[0].astype(int))
        p2 = tuple(length_endpoints[1].astype(int))
        cv2.line(img, p1, p2, (0, 255, 255), 2)
        # Length label at midpoint
        mid = ((p1[0] + p2[0]) // 2, (p1[1] + p2[1]) // 2)
        label = f"{length_mm:.1f} mm"
        cv2.putText(img, label, (mid[0] + 5, mid[1] - 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)

    # Draw width line (yellow, perpendicular)
    if width_endpoints is not None:
        p1 = tuple(width_endpoints[0].astype(int))
        p2 = tuple(width_endpoints[1].astype(int))
        cv2.line(img, p1, p2, (0, 255, 255), 2)
        mid = ((p1[0] + p2[0]) // 2, (p1[1] + p2[1]) // 2)
        label = f"{width_mm:.1f} mm"
        cv2.putText(img, label, (mid[0] + 5, mid[1] - 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)

    # Draw deepest point (red crosshair + depth label)
    if deepest_point_px is not None and max_depth_mm > 0:
        cx, cy = int(deepest_point_px[0]), int(deepest_point_px[1])
        cross_size = 12
        cv2.line(img, (cx - cross_size, cy), (cx + cross_size, cy), (0, 0, 255), 2)
        cv2.line(img, (cx, cy - cross_size), (cx, cy + cross_size), (0, 0, 255), 2)
        cv2.circle(img, (cx, cy), cross_size, (0, 0, 255), 1)
        label = f"{max_depth_mm:.1f} mm"
        cv2.putText(img, label, (cx + 15, cy + 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 2)

    # Encode as JPEG base64
    img_rgb = cv2.cvtColor(img, cv2.COLOR_RGB2BGR) if img.shape[2] == 3 else img
    _, buf = cv2.imencode(".jpg", img_rgb, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return base64.b64encode(buf.tobytes()).decode("utf-8")
