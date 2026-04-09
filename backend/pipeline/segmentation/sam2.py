"""SAM 2 (Segment Anything Model 2) wound segmentation.

Uses SAM 2.1 Hiera-L backbone for high-quality wound segmentation.
Supports point prompts (from iOS wound_point) and automatic mode.
"""

import logging
import os

import cv2
import numpy as np
import torch

from pipeline.segmentation.base import BaseSegmenter
from app.config import settings

logger = logging.getLogger("woundos.segmentation.sam2")

_instance: "SAM2Segmenter | None" = None


class SAM2Segmenter(BaseSegmenter):
    """SAM 2 wound segmentation with point prompt support."""

    def __init__(self):
        logger.info("Loading SAM 2 model...")
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        checkpoint = os.path.join(settings.sam2_model_path, settings.sam2_checkpoint)

        from sam2.build_sam import build_sam2
        from sam2.sam2_image_predictor import SAM2ImagePredictor
        import sam2

        # The sam2 package uses Hydra for config. We need to point Hydra's
        # config search path to the sam2 package's configs directory.
        sam2_pkg_dir = os.path.dirname(sam2.__file__)
        configs_dir = os.path.join(sam2_pkg_dir, "configs")

        # Inject the sam2 configs dir into Hydra's search path
        from hydra.core.global_hydra import GlobalHydra
        GlobalHydra.instance().clear()

        from hydra import initialize_config_dir
        with initialize_config_dir(config_dir=configs_dir, version_base="1.2"):
            model = build_sam2(
                config_file="sam2.1/sam2.1_hiera_l",
                ckpt_path=checkpoint,
                device=self.device,
            )

        self.predictor = SAM2ImagePredictor(model)
        logger.info("SAM 2 loaded on %s", self.device)

    def segment(
        self,
        image: np.ndarray,
        point_prompt: tuple[int, int] | None = None,
    ) -> np.ndarray:
        """Segment wound using SAM 2.

        Args:
            image: (H, W, 3) RGB uint8 image.
            point_prompt: Optional (x, y) pixel coordinate as positive seed.

        Returns:
            (H, W) uint8 binary mask (255=wound, 0=background).
        """
        self.predictor.set_image(image)

        if point_prompt is not None:
            # Use point prompt as positive seed
            input_point = np.array([[point_prompt[0], point_prompt[1]]])
            input_label = np.array([1])  # 1 = foreground
            masks, scores, _ = self.predictor.predict(
                point_coords=input_point,
                point_labels=input_label,
                multimask_output=True,
            )
            # Select highest-scoring mask
            best_idx = scores.argmax()
            mask = masks[best_idx]
        else:
            # Automatic mode: use center point as seed, then filter
            h, w = image.shape[:2]
            center_point = np.array([[w // 2, h // 2]])
            center_label = np.array([1])
            masks, scores, _ = self.predictor.predict(
                point_coords=center_point,
                point_labels=center_label,
                multimask_output=True,
            )
            # Select best mask by score + area filtering
            mask = self._select_best_mask(masks, scores, h, w)

        # Convert boolean mask to uint8
        result = (mask.astype(np.uint8)) * 255
        return result

    def _select_best_mask(
        self,
        masks: np.ndarray,
        scores: np.ndarray,
        h: int,
        w: int,
    ) -> np.ndarray:
        """Select the best mask from multi-mask output using clinical heuristics.

        Filters by:
        - Area: must be between 1% and 50% of image
        - Compactness: Polsby-Popper score > 0.3 (wound-like shape)
        - Score: prefer higher SAM confidence
        """
        total_pixels = h * w
        best_mask = None
        best_score = -1

        for i in range(len(masks)):
            mask = masks[i]
            area = mask.sum()
            area_ratio = area / total_pixels

            # Filter by area
            if area_ratio < 0.01 or area_ratio > 0.50:
                continue

            # Compute compactness (Polsby-Popper)
            mask_uint8 = mask.astype(np.uint8) * 255
            contours, _ = cv2.findContours(mask_uint8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if not contours:
                continue
            largest = max(contours, key=cv2.contourArea)
            perimeter = cv2.arcLength(largest, True)
            if perimeter < 1e-6:
                continue
            compactness = 4 * np.pi * area / (perimeter ** 2)

            if compactness < 0.3:
                continue

            # Score: combine SAM score + area preference (prefer medium-sized)
            combined_score = float(scores[i]) + 0.1 * (1.0 - abs(area_ratio - 0.1))
            if combined_score > best_score:
                best_score = combined_score
                best_mask = mask

        if best_mask is None:
            # Fallback: just use highest-scoring mask
            best_mask = masks[scores.argmax()]

        return best_mask


def get_sam2_segmenter() -> SAM2Segmenter:
    """Get or create the singleton SAM 2 segmenter."""
    global _instance
    if _instance is None:
        _instance = SAM2Segmenter()
    return _instance
