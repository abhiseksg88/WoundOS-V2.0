"""Abstract base class for depth estimation models."""

from abc import ABC, abstractmethod

import numpy as np


class BaseDepthEstimator(ABC):
    """Base class for metric depth estimation."""

    @abstractmethod
    def estimate_depth(
        self,
        image: np.ndarray,
        intrinsics: dict | None = None,
    ) -> np.ndarray:
        """Estimate metric depth from a single image.

        Args:
            image: (H, W, 3) RGB uint8 image.
            intrinsics: Optional camera intrinsics {fx, fy, cx, cy, width, height}.

        Returns:
            (H, W) float32 depth map in meters.
        """
        ...

    @abstractmethod
    def estimate_depth_batch(
        self,
        images: list[np.ndarray],
        intrinsics: dict | None = None,
    ) -> list[np.ndarray]:
        """Estimate depth for multiple images.

        Args:
            images: List of (H, W, 3) RGB uint8 images.
            intrinsics: Optional shared camera intrinsics.

        Returns:
            List of (H, W) float32 depth maps in meters.
        """
        ...
