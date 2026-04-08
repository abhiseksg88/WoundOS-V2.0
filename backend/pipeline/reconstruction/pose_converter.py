"""Convert ARKit camera poses to COLMAP format.

ARKit coordinate system: X-right, Y-up, Z-toward-viewer (OpenGL/right-handed)
COLMAP coordinate system: X-right, Y-down, Z-forward (OpenCV/right-handed)

ARKit provides camera-to-world (C2W) 4x4 transform matrices.
COLMAP expects world-to-camera (W2C) with quaternion (qw,qx,qy,qz) + translation (tx,ty,tz).
"""

import os
import logging

import numpy as np

logger = logging.getLogger("woundos.pose_converter")

# Coordinate system conversion matrix: ARKit (OpenGL) -> COLMAP (OpenCV)
# Flip Y and Z axes
ARKIT_TO_COLMAP = np.array([
    [1,  0,  0],
    [0, -1,  0],
    [0,  0, -1],
], dtype=np.float64)


def rotation_matrix_to_quaternion(R: np.ndarray) -> tuple[float, float, float, float]:
    """Convert 3x3 rotation matrix to quaternion (qw, qx, qy, qz).

    Uses Shepperd's method for numerical stability.
    """
    trace = np.trace(R)

    if trace > 0:
        s = 0.5 / np.sqrt(trace + 1.0)
        qw = 0.25 / s
        qx = (R[2, 1] - R[1, 2]) * s
        qy = (R[0, 2] - R[2, 0]) * s
        qz = (R[1, 0] - R[0, 1]) * s
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        s = 2.0 * np.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2])
        qw = (R[2, 1] - R[1, 2]) / s
        qx = 0.25 * s
        qy = (R[0, 1] + R[1, 0]) / s
        qz = (R[0, 2] + R[2, 0]) / s
    elif R[1, 1] > R[2, 2]:
        s = 2.0 * np.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2])
        qw = (R[0, 2] - R[2, 0]) / s
        qx = (R[0, 1] + R[1, 0]) / s
        qy = 0.25 * s
        qz = (R[1, 2] + R[2, 1]) / s
    else:
        s = 2.0 * np.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1])
        qw = (R[1, 0] - R[0, 1]) / s
        qx = (R[0, 2] + R[2, 0]) / s
        qy = (R[1, 2] + R[2, 1]) / s
        qz = 0.25 * s

    return (qw, qx, qy, qz)


def arkit_to_colmap_pose(c2w_4x4: np.ndarray) -> tuple[tuple[float, ...], np.ndarray]:
    """Convert an ARKit camera-to-world 4x4 matrix to COLMAP world-to-camera.

    Args:
        c2w_4x4: 4x4 camera-to-world transform from ARKit.

    Returns:
        (quaternion, translation): quaternion as (qw, qx, qy, qz),
            translation as (tx, ty, tz) numpy array.
    """
    c2w = np.array(c2w_4x4, dtype=np.float64)
    R_c2w = c2w[:3, :3]
    t_c2w = c2w[:3, 3]

    # Convert coordinate system
    R_c2w_colmap = ARKIT_TO_COLMAP @ R_c2w
    t_c2w_colmap = ARKIT_TO_COLMAP @ t_c2w

    # Invert: world-to-camera
    R_w2c = R_c2w_colmap.T
    t_w2c = -R_w2c @ t_c2w_colmap

    quat = rotation_matrix_to_quaternion(R_w2c)
    return (quat, t_w2c)


def write_colmap_files(
    output_dir: str,
    intrinsics: dict,
    poses: list[dict],
    frame_filenames: list[str],
) -> None:
    """Write COLMAP text-format model files for known-pose MVS.

    Creates:
      - cameras.txt (single PINHOLE camera)
      - images.txt (one line per image with W2C pose)
      - points3D.txt (empty — no prior 3D points)

    Args:
        output_dir: Directory to write the files to.
        intrinsics: Dict with keys fx, fy, cx, cy, width, height.
        poses: List of pose dicts with 'transform' (4x4 list of lists).
        frame_filenames: List of image filenames matching poses order.
    """
    os.makedirs(output_dir, exist_ok=True)

    # cameras.txt — single shared PINHOLE camera
    fx = intrinsics["fx"]
    fy = intrinsics["fy"]
    cx = intrinsics["cx"]
    cy = intrinsics["cy"]
    w = intrinsics["width"]
    h = intrinsics["height"]

    cameras_path = os.path.join(output_dir, "cameras.txt")
    with open(cameras_path, "w") as f:
        f.write("# Camera list with one line of data per camera:\n")
        f.write("#   CAMERA_ID, MODEL, WIDTH, HEIGHT, PARAMS[]\n")
        f.write(f"1 PINHOLE {w} {h} {fx} {fy} {cx} {cy}\n")

    # images.txt — one entry per image
    images_path = os.path.join(output_dir, "images.txt")
    with open(images_path, "w") as f:
        f.write("# Image list with two lines of data per image:\n")
        f.write("#   IMAGE_ID, QW, QX, QY, QZ, TX, TY, TZ, CAMERA_ID, NAME\n")
        f.write("#   POINTS2D[] as (X, Y, POINT3D_ID) — empty for known poses\n")

        for i, (pose, filename) in enumerate(zip(poses, frame_filenames)):
            image_id = i + 1
            c2w_4x4 = np.array(pose["transform"], dtype=np.float64)
            quat, tvec = arkit_to_colmap_pose(c2w_4x4)
            qw, qx, qy, qz = quat
            tx, ty, tz = tvec

            f.write(f"{image_id} {qw} {qx} {qy} {qz} {tx} {ty} {tz} 1 {filename}\n")
            f.write("\n")  # Empty line — no 2D point observations

    # points3D.txt — empty
    points_path = os.path.join(output_dir, "points3D.txt")
    with open(points_path, "w") as f:
        f.write("# 3D point list (empty — using known poses for MVS)\n")

    logger.info(
        "Wrote COLMAP model files to %s: %d cameras, %d images",
        output_dir, 1, len(poses),
    )
