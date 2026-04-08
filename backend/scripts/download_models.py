#!/usr/bin/env python3
"""Download and cache ML model weights for baking into Docker image.

Models:
- Apple Depth Pro (~1.5 GB)
- SAM 2.1 Hiera-L (~900 MB)
"""

import os
import subprocess
import sys


def download_depth_pro():
    """Download Depth Pro model weights."""
    model_dir = "/models/depth_pro"
    os.makedirs(model_dir, exist_ok=True)

    print("Downloading Depth Pro model...")
    # Depth Pro auto-downloads on first use via HuggingFace Hub
    # Trigger the download by importing and creating the model
    try:
        import depth_pro
        model, transform = depth_pro.create_model_and_transforms()
        print(f"Depth Pro model loaded successfully")
        del model, transform
    except Exception as e:
        print(f"Warning: Could not pre-download Depth Pro: {e}")
        print("Model will be downloaded on first use.")


def download_sam2():
    """Download SAM 2.1 Hiera-L model weights."""
    model_dir = "/models/sam2"
    os.makedirs(model_dir, exist_ok=True)

    checkpoint_url = "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_large.pt"
    checkpoint_path = os.path.join(model_dir, "sam2.1_hiera_large.pt")

    if not os.path.exists(checkpoint_path):
        print(f"Downloading SAM 2.1 Hiera-L to {checkpoint_path}...")
        subprocess.run([
            "wget", "-q", "--show-progress",
            "-O", checkpoint_path,
            checkpoint_url,
        ], check=True)
        print(f"SAM 2.1 downloaded ({os.path.getsize(checkpoint_path) / 1e9:.1f} GB)")
    else:
        print(f"SAM 2.1 already exists at {checkpoint_path}")


def main():
    print("=== Downloading ML models for WoundOS V2 ===")

    download_sam2()
    download_depth_pro()

    print("\n=== All models downloaded ===")


if __name__ == "__main__":
    main()
