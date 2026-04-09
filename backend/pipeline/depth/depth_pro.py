"""Apple Depth Pro — metric monocular depth estimation.

Depth Pro (Apple, 2024) produces high-resolution (2.25 Mpx) metric depth
maps without requiring camera intrinsics. It has the best boundary sharpness
(highest boundary F1 score) among all monocular depth models, which is
critical for wound edge precision.

Reference: https://github.com/apple/ml-depth-pro
"""

import logging

import numpy as np
import torch
from PIL import Image

from app.config import settings
from pipeline.depth.base import BaseDepthEstimator

logger = logging.getLogger("woundos.depth.depth_pro")

_instance: "DepthProEstimator | None" = None


class DepthProEstimator(BaseDepthEstimator):
    """Apple Depth Pro metric depth estimator."""

    def __init__(self):
        logger.info("Loading Depth Pro model...")
        import depth_pro
        from depth_pro import DepthProConfig

        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        # Depth Pro defaults to ./checkpoints/depth_pro.pt which doesn't exist
        # in our Docker container. Use HuggingFace Hub cached path or our
        # pre-downloaded path.
        checkpoint_path = self._find_checkpoint()
        logger.info("Depth Pro checkpoint: %s", checkpoint_path)

        config = DepthProConfig(
            patch_encoder_preset="dinov2l16_384",
            image_encoder_preset="dinov2l16_384",
            checkpoint_uri=checkpoint_path,
            decoder_features=256,
            use_fov_head=True,
            fov_encoder_preset="dinov2l16_384",
        )

        self.model, self.transform = depth_pro.create_model_and_transforms(
            config=config,
            device=self.device,
        )
        self.model.eval()
        logger.info("Depth Pro loaded on %s", self.device)

    def _find_checkpoint(self) -> str:
        """Find Depth Pro checkpoint from local paths or HuggingFace cache."""
        import os

        # Check pre-downloaded locations
        candidates = [
            os.path.join(settings.depth_pro_model_path, "depth_pro.pt"),
            "/models/depth_pro/depth_pro.pt",
            "./checkpoints/depth_pro.pt",
        ]
        for path in candidates:
            if os.path.exists(path):
                return path

        # Download from HuggingFace Hub
        logger.info("Depth Pro checkpoint not found locally, downloading from HuggingFace...")
        from huggingface_hub import hf_hub_download
        return hf_hub_download(repo_id="apple/DepthPro", filename="depth_pro.pt")

    @torch.no_grad()
    def estimate_depth(
        self,
        image: np.ndarray,
        intrinsics: dict | None = None,
    ) -> np.ndarray:
        """Estimate metric depth from a single RGB image.

        Args:
            image: (H, W, 3) RGB uint8 numpy array.
            intrinsics: Optional intrinsics (Depth Pro doesn't require them
                but can use them for validation).

        Returns:
            (H, W) float32 depth map in meters.
        """
        pil_image = Image.fromarray(image)
        input_tensor = self.transform(pil_image).to(self.device)

        prediction = self.model.infer(input_tensor)
        depth = prediction["depth"].cpu().numpy()  # (H, W) in meters

        # If intrinsics provided, Depth Pro also returns focal length estimate
        # We can cross-validate: predicted_fl vs ARKit fx
        if intrinsics and "focallength_px" in prediction:
            pred_fl = prediction["focallength_px"].item()
            arkit_fl = intrinsics.get("fx", 0)
            if arkit_fl > 0:
                fl_ratio = pred_fl / arkit_fl
                if abs(fl_ratio - 1.0) > 0.2:
                    logger.warning(
                        "Focal length mismatch: predicted=%.1f, ARKit=%.1f (ratio=%.2f)",
                        pred_fl, arkit_fl, fl_ratio,
                    )

        return depth.astype(np.float32)

    @torch.no_grad()
    def estimate_depth_batch(
        self,
        images: list[np.ndarray],
        intrinsics: dict | None = None,
    ) -> list[np.ndarray]:
        """Estimate depth for multiple images sequentially.

        Depth Pro processes one image at a time (no batch mode in the public API).
        At ~0.3s per frame on L4 GPU, 30 frames takes ~9s.
        """
        depth_maps = []
        for i, image in enumerate(images):
            depth = self.estimate_depth(image, intrinsics)
            depth_maps.append(depth)
            if (i + 1) % 10 == 0:
                logger.info("Depth estimation: %d/%d frames", i + 1, len(images))

        logger.info("Depth estimation complete: %d frames", len(images))
        return depth_maps


def get_depth_pro() -> DepthProEstimator:
    """Get or create the singleton Depth Pro estimator."""
    global _instance
    if _instance is None:
        _instance = DepthProEstimator()
    return _instance
