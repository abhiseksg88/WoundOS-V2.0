"""Generate annotated wound image with boundary, dimension lines, L/W markers, and depth marker.

Renders the clinical "L × W cross" overlay used by Apple Measure-style wound apps:
- Green smooth wound contour with semi-transparent fill
- Length axis: yellow line with green "L" markers at both endpoints
- Width axis: yellow line with green "W" markers at both endpoints
- Optional wound label badge (e.g. "W1") near the right edge of the wound
- Optional deepest point crosshair (red)
"""

import base64

import cv2
import numpy as np


# Marker styling — clinical green, like the screenshot reference
_MARKER_COLOR = (0, 220, 90)        # BGR — bright clinical green
_MARKER_BORDER_COLOR = (0, 90, 30)  # darker outline
_LINE_COLOR = (0, 220, 90)          # cross axis lines, same green
_LABEL_COLOR = (255, 255, 255)
_LABEL_FONT = cv2.FONT_HERSHEY_SIMPLEX


def generate_annotated_image(
    frame: np.ndarray,
    wound_contour: np.ndarray,
    length_mm: float,
    width_mm: float,
    length_endpoints: tuple[np.ndarray, np.ndarray] | None = None,
    width_endpoints: tuple[np.ndarray, np.ndarray] | None = None,
    deepest_point_px: tuple[int, int] | None = None,
    max_depth_mm: float = 0.0,
    wound_label: str | None = None,
) -> str:
    """Draw wound boundary, L/W cross, and label markers on a frame.

    Args:
        frame: (H, W, 3) RGB image.
        wound_contour: (N, 2) array of contour points in pixel coordinates.
        length_mm: Greatest length measurement (for the line label, optional).
        width_mm: Greatest width measurement (for the line label, optional).
        length_endpoints: Optional (start, end) pixel coordinates for length line.
        width_endpoints: Optional (start, end) pixel coordinates for width line.
        deepest_point_px: Optional (x, y) pixel coordinates of deepest point.
        max_depth_mm: Maximum depth value for label.
        wound_label: Optional badge text (e.g. "W1") drawn near the wound.

    Returns:
        Base64-encoded JPEG string.
    """
    img = frame.copy()
    h, w = img.shape[:2]

    # 1. Wound boundary contour with fill
    if len(wound_contour) > 0:
        contour_int = wound_contour.astype(np.int32).reshape(-1, 1, 2)

        # Semi-transparent green fill (20% opacity)
        overlay = img.copy()
        cv2.fillPoly(overlay, [contour_int], _MARKER_COLOR)
        cv2.addWeighted(overlay, 0.18, img, 0.82, 0, img)

        # Solid green outline (3px)
        cv2.drawContours(img, [contour_int], -1, _MARKER_COLOR, 3, lineType=cv2.LINE_AA)

    # 2. Length cross-axis line + L markers at both endpoints
    if length_endpoints is not None:
        try:
            p1 = (int(length_endpoints[0][0]), int(length_endpoints[0][1]))
            p2 = (int(length_endpoints[1][0]), int(length_endpoints[1][1]))
            if _is_in_bounds(p1, w, h) and _is_in_bounds(p2, w, h):
                cv2.line(img, p1, p2, _LINE_COLOR, 2, lineType=cv2.LINE_AA)
                _draw_letter_marker(img, p1, "L")
                _draw_letter_marker(img, p2, "L")
        except (TypeError, ValueError, IndexError):
            pass

    # 3. Width cross-axis line + W markers at both endpoints
    if width_endpoints is not None:
        try:
            p1 = (int(width_endpoints[0][0]), int(width_endpoints[0][1]))
            p2 = (int(width_endpoints[1][0]), int(width_endpoints[1][1]))
            if _is_in_bounds(p1, w, h) and _is_in_bounds(p2, w, h):
                cv2.line(img, p1, p2, _LINE_COLOR, 2, lineType=cv2.LINE_AA)
                _draw_letter_marker(img, p1, "W")
                _draw_letter_marker(img, p2, "W")
        except (TypeError, ValueError, IndexError):
            pass

    # 4. Wound label badge (e.g. "W1")
    if wound_label and len(wound_contour) > 0:
        # Place near the right edge of the wound
        contour_pts = wound_contour.astype(np.int32)
        right_idx = int(np.argmax(contour_pts[:, 0]))
        anchor = (
            int(contour_pts[right_idx, 0]) + 12,
            int(contour_pts[right_idx, 1]) + 8,
        )
        _draw_label_badge(img, anchor, wound_label)

    # 5. Deepest point crosshair (red)
    if deepest_point_px is not None and max_depth_mm > 0:
        cx, cy = int(deepest_point_px[0]), int(deepest_point_px[1])
        cross_size = 12
        cv2.line(img, (cx - cross_size, cy), (cx + cross_size, cy), (0, 0, 255), 2)
        cv2.line(img, (cx, cy - cross_size), (cx, cy + cross_size), (0, 0, 255), 2)
        cv2.circle(img, (cx, cy), cross_size, (0, 0, 255), 1)
        label = f"{max_depth_mm:.1f} mm"
        cv2.putText(img, label, (cx + 15, cy + 5),
                    _LABEL_FONT, 0.5, (0, 0, 255), 2)

    # Encode as JPEG base64
    img_bgr = cv2.cvtColor(img, cv2.COLOR_RGB2BGR) if img.shape[2] == 3 else img
    _, buf = cv2.imencode(".jpg", img_bgr, [cv2.IMWRITE_JPEG_QUALITY, 90])
    return base64.b64encode(buf.tobytes()).decode("utf-8")


def _draw_letter_marker(img: np.ndarray, center: tuple[int, int], letter: str) -> None:
    """Draw a filled green circle with a single white letter (L or W)."""
    cx, cy = center
    radius = 16
    # Outer white halo
    cv2.circle(img, (cx, cy), radius + 1, (255, 255, 255), 1, lineType=cv2.LINE_AA)
    # Filled green circle
    cv2.circle(img, (cx, cy), radius, _MARKER_COLOR, -1, lineType=cv2.LINE_AA)
    # Dark border for contrast
    cv2.circle(img, (cx, cy), radius, _MARKER_BORDER_COLOR, 2, lineType=cv2.LINE_AA)

    # Center the letter
    font_scale = 0.7
    thickness = 2
    text_size, _ = cv2.getTextSize(letter, _LABEL_FONT, font_scale, thickness)
    tx = cx - text_size[0] // 2
    ty = cy + text_size[1] // 2
    cv2.putText(img, letter, (tx, ty), _LABEL_FONT, font_scale,
                _LABEL_COLOR, thickness, lineType=cv2.LINE_AA)


def _draw_label_badge(img: np.ndarray, anchor: tuple[int, int], text: str) -> None:
    """Draw a small wound identifier badge (e.g. "W1") with green background."""
    cx, cy = anchor
    h, w = img.shape[:2]

    font_scale = 0.55
    thickness = 2
    text_size, _ = cv2.getTextSize(text, _LABEL_FONT, font_scale, thickness)

    pad_x, pad_y = 8, 6
    box_w = text_size[0] + 2 * pad_x
    box_h = text_size[1] + 2 * pad_y

    # Clamp to image bounds
    x1 = min(max(cx, 0), w - box_w)
    y1 = min(max(cy, 0), h - box_h)
    x2 = x1 + box_w
    y2 = y1 + box_h

    cv2.rectangle(img, (x1, y1), (x2, y2), _MARKER_COLOR, -1, lineType=cv2.LINE_AA)
    cv2.rectangle(img, (x1, y1), (x2, y2), _MARKER_BORDER_COLOR, 2, lineType=cv2.LINE_AA)

    tx = x1 + pad_x
    ty = y1 + pad_y + text_size[1]
    cv2.putText(img, text, (tx, ty), _LABEL_FONT, font_scale,
                _LABEL_COLOR, thickness, lineType=cv2.LINE_AA)


def _is_in_bounds(point: tuple[int, int], width: int, height: int) -> bool:
    return 0 <= point[0] < width and 0 <= point[1] < height
