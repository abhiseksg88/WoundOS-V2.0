"""Abstract base class for wound segmentation."""

from abc import ABC, abstractmethod

import numpy as np


class BaseSegmenter(ABC):
    """Base class for wound segmentation models."""

    @abstractmethod
    def segment(
        self,
        image: np.ndarray,
        point_prompt: tuple[int, int] | None = None,
    ) -> np.ndarray:
        """Segment the wound from an image.

        Args:
            image: (H, W, 3) RGB uint8 image.
            point_prompt: Optional (x, y) pixel coordinate as positive seed.

        Returns:
            (H, W) uint8 binary mask where 255=wound, 0=background.
        """
        ...
