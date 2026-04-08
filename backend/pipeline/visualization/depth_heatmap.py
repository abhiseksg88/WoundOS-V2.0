"""Generate depth heatmap visualization (green=shallow, yellow=mid, red=deep)."""

import base64
import io

import cv2
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.cm as cm


def generate_depth_heatmap(
    frame: np.ndarray,
    wound_mask: np.ndarray,
    depth_map: np.ndarray,
    max_depth_mm: float = 6.0,
) -> str:
    """Generate a depth heatmap overlaid on the wound region.

    Color mapping: green (0mm) -> yellow (3mm) -> red (6mm+)

    Args:
        frame: (H, W, 3) RGB image.
        wound_mask: (H, W) binary mask (255=wound).
        depth_map: (H, W) float depth values in millimeters.
        max_depth_mm: Maximum depth for colormap scaling.

    Returns:
        Base64-encoded JPEG string.
    """
    h, w = frame.shape[:2]
    img = frame.copy()

    # Normalize depth to 0-1 range
    depth_norm = np.clip(depth_map / max(max_depth_mm, 0.01), 0.0, 1.0)

    # Use RdYlGn_r colormap (green=low, yellow=mid, red=high)
    colormap = cm.get_cmap("RdYlGn_r")
    depth_colored = (colormap(depth_norm)[:, :, :3] * 255).astype(np.uint8)

    # Apply only to wound region
    wound_region = wound_mask > 127
    overlay = img.copy()
    overlay[wound_region] = depth_colored[wound_region]

    # Blend with original (70% heatmap, 30% original for wound area)
    result = img.copy()
    result[wound_region] = cv2.addWeighted(
        overlay[wound_region], 0.7,
        img[wound_region], 0.3,
        0,
    )

    # Draw color legend bar at bottom
    legend_h = 30
    legend_w = min(w - 40, 300)
    legend_x = 20
    legend_y = h - legend_h - 20

    for i in range(legend_w):
        t = i / legend_w
        color = np.array(colormap(t)[:3]) * 255
        cv2.line(result, (legend_x + i, legend_y),
                 (legend_x + i, legend_y + legend_h),
                 color.astype(int).tolist(), 1)

    # Legend labels
    cv2.putText(result, "0mm", (legend_x, legend_y - 5),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
    cv2.putText(result, f"{max_depth_mm:.0f}mm", (legend_x + legend_w - 30, legend_y - 5),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)

    # Encode as JPEG base64
    img_bgr = cv2.cvtColor(result, cv2.COLOR_RGB2BGR)
    _, buf = cv2.imencode(".jpg", img_bgr, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return base64.b64encode(buf.tobytes()).decode("utf-8")
