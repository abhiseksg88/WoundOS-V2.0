#!/usr/bin/env python3
"""Download and cache ML model weights for baking into Docker image.

Models:
- Apple Depth Pro (~1.5 GB) — downloaded via HuggingFace Hub
- SAM 2.1 Hiera-L (~900 MB) — pre-cached via HuggingFace Hub
"""

import os


def download_depth_pro():
    """Download Depth Pro model weights via HuggingFace Hub."""
    print("Downloading Depth Pro model weights...")
    try:
        from huggingface_hub import hf_hub_download
        checkpoint = hf_hub_download(
            repo_id="apple/DepthPro",
            filename="depth_pro.pt",
            local_dir="/models/depth_pro",
        )
        print(f"Depth Pro weights downloaded to {checkpoint}")
    except Exception as e:
        print(f"Warning: Depth Pro download failed: {e}")
        print("Model will be downloaded on first use at runtime.")


def download_sam2_hf():
    """Pre-cache SAM 2.1 HuggingFace model files.

    This ensures from_pretrained() doesn't need internet at runtime.
    """
    print("Pre-caching SAM 2.1 HuggingFace model files...")
    try:
        from huggingface_hub import snapshot_download
        path = snapshot_download(
            repo_id="facebook/sam2.1-hiera-large",
            local_dir="/models/sam2_hf",
        )
        print(f"SAM 2.1 HF model cached to {path}")
    except Exception as e:
        print(f"Warning: SAM 2.1 HF cache failed: {e}")
        print("Model will be downloaded on first use at runtime.")


def main():
    print("=== Downloading ML models for WoundOS V2 ===")

    # SAM 2 checkpoint (wget in Dockerfile)
    sam2_path = "/models/sam2/sam2.1_hiera_large.pt"
    if os.path.exists(sam2_path):
        size_gb = os.path.getsize(sam2_path) / 1e9
        print(f"SAM 2.1 checkpoint: {sam2_path} ({size_gb:.1f} GB)")

    # Pre-cache SAM 2.1 HuggingFace model (for from_pretrained)
    download_sam2_hf()

    # Download Depth Pro
    download_depth_pro()

    print("\n=== Model download complete ===")


if __name__ == "__main__":
    main()
