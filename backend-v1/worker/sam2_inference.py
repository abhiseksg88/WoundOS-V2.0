"""SAM 2 CPU inference for shadow validation.

Uses SAM 2 Tiny (facebook/sam2.1-hiera-tiny) via the from_pretrained API,
which bypasses Hydra configuration entirely. Runs on CPU only — no GPU, no
CUDA required.
"""

from __future__ import annotations

import logging

import numpy as np
import torch

logger = logging.getLogger(__name__)

SAM2_MODEL_ID = "facebook/sam2.1-hiera-tiny"


class SAM2Predictor:
    """Wrapper around SAM 2 image predictor for CPU inference."""

    def __init__(self) -> None:
        """Load SAM 2 model from HuggingFace Hub using from_pretrained."""
        from sam2.sam2_image_predictor import SAM2ImagePredictor

        logger.info("Loading SAM 2 model: %s (CPU)", SAM2_MODEL_ID)
        self._predictor = SAM2ImagePredictor.from_pretrained(
            SAM2_MODEL_ID, device="cpu"
        )
        logger.info("SAM 2 model loaded successfully")

    def predict(
        self,
        image: np.ndarray,
        point_coords: list[list[float]],
        point_labels: list[int],
    ) -> np.ndarray:
        """Run SAM 2 inference on a single image with point prompts.

        Args:
            image: RGB image as numpy array, shape (H, W, 3), dtype uint8.
            point_coords: List of [x, y] coordinates for point prompts.
            point_labels: List of labels (1=foreground, 0=background) for each point.

        Returns:
            Binary mask as uint8 numpy array, shape (H, W), values 0 or 1.
        """
        with torch.inference_mode():
            self._predictor.set_image(image)

            coords_np = np.array(point_coords, dtype=np.float32)
            labels_np = np.array(point_labels, dtype=np.int32)

            masks, scores, _ = self._predictor.predict(
                point_coords=coords_np,
                point_labels=labels_np,
                multimask_output=True,
            )

        # Select the mask with the highest confidence score
        best_idx = int(np.argmax(scores))
        best_mask = masks[best_idx]

        # Convert to binary uint8 mask
        binary_mask = (best_mask > 0).astype(np.uint8)

        logger.info(
            "SAM 2 prediction: %d masks, best score=%.4f, mask area=%d px",
            len(scores),
            scores[best_idx],
            int(binary_mask.sum()),
        )

        return binary_mask
