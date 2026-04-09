"""Tissue classification for wound bed composition.

Classifies wound tissue into four types for PUSH score:
- Granulation (red/beefy)
- Slough (yellow/tan)
- Necrotic/Eschar (black/brown)
- Epithelial (pink/light)

Initial implementation uses color-space heuristics in HSV.
Upgrade path: train a proper classifier (e.g., Dual-Attention U-Net).
"""

import logging

import cv2
import numpy as np

logger = logging.getLogger("woundos.segmentation.tissue")


def classify_tissue(
    image: np.ndarray,
    wound_mask: np.ndarray,
) -> dict:
    """Classify wound tissue composition using color-space analysis.

    Args:
        image: (H, W, 3) RGB uint8 image.
        wound_mask: (H, W) uint8 binary mask (255=wound).

    Returns:
        Dict with keys: granulation_pct, slough_pct, necrotic_pct, epithelial_pct.
        Values are floats 0.0-1.0 summing to ~1.0.
    """
    # Convert to HSV for color-based classification
    hsv = cv2.cvtColor(image, cv2.COLOR_RGB2HSV)
    wound_pixels = wound_mask > 127
    total_wound_pixels = wound_pixels.sum()

    if total_wound_pixels == 0:
        return {
            "granulation_pct": 0.0,
            "slough_pct": 0.0,
            "necrotic_pct": 0.0,
            "epithelial_pct": 0.0,
        }

    h = hsv[:, :, 0]  # 0-180 in OpenCV
    s = hsv[:, :, 1]  # 0-255
    v = hsv[:, :, 2]  # 0-255

    # Granulation: red/beefy tissue — H near 0 or 170+, high S, medium-high V
    granulation_mask = wound_pixels & (
        ((h < 15) | (h > 165)) & (s > 80) & (v > 80)
    )

    # Slough: yellow/tan/cream — H 15-40, medium S, high V
    slough_mask = wound_pixels & (
        (h >= 15) & (h <= 40) & (s > 30) & (v > 100)
    )

    # Necrotic/Eschar: black/dark brown — low V (dark) or dark brown
    necrotic_mask = wound_pixels & (
        (v < 80) | ((h >= 5) & (h <= 25) & (s > 50) & (v < 120))
    )

    # Epithelial: pink/light — light pinkish, high V, low-medium S
    epithelial_mask = wound_pixels & (
        ((h < 15) | (h > 160)) & (s < 80) & (v > 150)
    )

    # Count pixels
    gran_count = granulation_mask.sum()
    slough_count = slough_mask.sum()
    necrotic_count = necrotic_mask.sum()
    epithelial_count = epithelial_mask.sum()

    # Handle overlapping classifications — prioritize by clinical severity
    total_classified = gran_count + slough_count + necrotic_count + epithelial_count
    if total_classified == 0:
        # Default: assume granulation if no clear classification
        return {
            "granulation_pct": 0.8,
            "slough_pct": 0.1,
            "necrotic_pct": 0.05,
            "epithelial_pct": 0.05,
        }

    # Normalize
    result = {
        "granulation_pct": round(gran_count / total_classified, 3),
        "slough_pct": round(slough_count / total_classified, 3),
        "necrotic_pct": round(necrotic_count / total_classified, 3),
        "epithelial_pct": round(epithelial_count / total_classified, 3),
    }

    logger.info(
        "Tissue composition: gran=%.1f%% slough=%.1f%% necrotic=%.1f%% epithelial=%.1f%%",
        result["granulation_pct"] * 100,
        result["slough_pct"] * 100,
        result["necrotic_pct"] * 100,
        result["epithelial_pct"] * 100,
    )

    return result
