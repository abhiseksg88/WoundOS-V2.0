"""Agreement metrics between nurse boundary mask and SAM 2 predicted mask.

Computes IoU, Dice coefficient, area delta percentage, and centroid
displacement in pixels.
"""

from __future__ import annotations

import numpy as np


def compute_agreement_metrics(
    nurse_mask: np.ndarray,
    sam2_mask: np.ndarray,
) -> dict[str, float]:
    """Compute agreement metrics between two binary masks.

    Args:
        nurse_mask: Binary mask from nurse boundary, shape (H, W), values 0/1.
        sam2_mask: Binary mask from SAM 2 prediction, shape (H, W), values 0/1.

    Returns:
        Dictionary with keys: iou, dice, area_delta_percent,
        centroid_displacement_px.
    """
    # Ensure masks are boolean for set operations
    nurse = nurse_mask.astype(bool)
    sam2 = sam2_mask.astype(bool)

    intersection = np.logical_and(nurse, sam2).sum()
    union = np.logical_or(nurse, sam2).sum()

    nurse_area = nurse.sum()
    sam2_area = sam2.sum()

    # IoU
    iou = float(intersection / union) if union > 0 else 0.0

    # Dice coefficient
    dice_denom = nurse_area + sam2_area
    dice = float(2.0 * intersection / dice_denom) if dice_denom > 0 else 0.0

    # Area delta percentage: positive means SAM 2 mask is larger
    if nurse_area > 0:
        area_delta_percent = float((sam2_area - nurse_area) / nurse_area * 100.0)
    else:
        area_delta_percent = 0.0

    # Centroid displacement
    nurse_centroid = _compute_centroid(nurse)
    sam2_centroid = _compute_centroid(sam2)

    if nurse_centroid is not None and sam2_centroid is not None:
        centroid_displacement_px = float(
            np.sqrt(
                (nurse_centroid[0] - sam2_centroid[0]) ** 2
                + (nurse_centroid[1] - sam2_centroid[1]) ** 2
            )
        )
    else:
        centroid_displacement_px = 0.0

    return {
        "iou": iou,
        "dice": dice,
        "area_delta_percent": area_delta_percent,
        "centroid_displacement_px": centroid_displacement_px,
    }


def _compute_centroid(mask: np.ndarray) -> tuple[float, float] | None:
    """Compute the centroid (center of mass) of a binary mask.

    Args:
        mask: Boolean numpy array of shape (H, W).

    Returns:
        (x, y) centroid coordinates, or None if the mask is empty.
    """
    if mask.sum() == 0:
        return None

    # np.where returns (row_indices, col_indices) = (y_coords, x_coords)
    rows, cols = np.where(mask)
    cy = float(rows.mean())
    cx = float(cols.mean())

    return (cx, cy)
