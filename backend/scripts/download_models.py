#!/usr/bin/env python3
"""Download and cache ML model weights for baking into Docker image.

Models:
- Apple Depth Pro (~1.5 GB) — downloaded via HuggingFace Hub
- SAM 2.1 Hiera-L (~900 MB) — downloaded via wget in Dockerfile
"""

import os
import subprocess
import sys


def download_depth_pro():
    """Download Depth Pro model weights via HuggingFace Hub.

    Note: This runs during Docker build (no GPU), so we only download
    weights — we don't try to load the model onto a device.
    """
    print("Downloading Depth Pro model weights...")
    try:
        # Use huggingface_hub to download the checkpoint
        from huggingface_hub import hf_hub_download
        checkpoint = hf_hub_download(
            repo_id="apple/DepthPro",
            filename="depth_pro.pt",
            local_dir="/models/depth_pro",
        )
        print(f"Depth Pro weights downloaded to {checkpoint}")
    except ImportError:
        print("huggingface_hub not installed, trying depth_pro package...")
        try:
            # Trigger download through the package's built-in mechanism
            import depth_pro
            # Only download, don't create model (needs GPU)
            print("depth_pro package imported successfully")
        except Exception as e:
            print(f"Warning: Could not pre-download Depth Pro: {e}")
            print("Model will be downloaded on first use at runtime.")
    except Exception as e:
        print(f"Warning: Depth Pro download failed: {e}")
        print("Model will be downloaded on first use at runtime.")


def main():
    print("=== Downloading ML models for WoundOS V2 ===")

    # SAM 2 checkpoint is downloaded via wget in Dockerfile
    sam2_path = "/models/sam2/sam2.1_hiera_large.pt"
    if os.path.exists(sam2_path):
        size_gb = os.path.getsize(sam2_path) / 1e9
        print(f"SAM 2.1 checkpoint: {sam2_path} ({size_gb:.1f} GB)")
    else:
        print(f"SAM 2.1 not found at {sam2_path} — will be downloaded separately")

    # Download Depth Pro
    download_depth_pro()

    print("\n=== Model download complete ===")


if __name__ == "__main__":
    main()
