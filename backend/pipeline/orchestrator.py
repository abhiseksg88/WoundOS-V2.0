"""Pipeline Orchestrator — chains all processing tiers.

Tier 1 (5-8s):  Depth Pro → TSDF fusion → SAM 2 segmentation → measurements
Tier 2 (30-60s): COLMAP MVS → Poisson → Taubin → refined measurements
Tier 3 (optional): Gaussian Splatting → splat export
"""

import base64
import io
import logging
import time

import cv2
import numpy as np
import trimesh
from PIL import Image

from app.config import settings
from app.models.job import JobStatus
from app.services import firestore, storage

logger = logging.getLogger("woundos.orchestrator")

_instance: "PipelineOrchestrator | None" = None


class PipelineOrchestrator:
    """Orchestrates the tiered wound processing pipeline."""

    def __init__(self):
        logger.info("Initializing pipeline orchestrator...")
        # Lazy imports — models are loaded on first use
        self._depth_estimator = None
        self._segmenter = None

    @property
    def depth_estimator(self):
        if self._depth_estimator is None:
            from pipeline.depth.depth_pro import get_depth_pro
            self._depth_estimator = get_depth_pro()
        return self._depth_estimator

    @property
    def segmenter(self):
        if self._segmenter is None:
            from pipeline.segmentation.sam2 import get_sam2_segmenter
            self._segmenter = get_sam2_segmenter()
        return self._segmenter

    def process_lidar_scan(
        self,
        job_id: str,
        frame_bytes: bytes,
        pose: dict,
        intrinsics: dict,
        mesh_obj_bytes: bytes,
        wound_point: str | None = None,
    ) -> None:
        """Run the LiDAR-native pipeline (Tier 1 only, no COLMAP).

        Uses the iPhone LiDAR scene reconstruction mesh directly instead of
        running Depth Pro + TSDF + COLMAP MVS. Total time: 3-5 seconds.

        Steps:
        1. Parse OBJ mesh from bytes (already in ARKit world coordinates)
        2. SAM 2 segmentation on the single best frame
        3. Ray-cast wound point against mesh to find world-space center
        4. Crop mesh to sphere around wound (8cm radius)
        5. Project wound mask onto cropped mesh (reuses _extract_wound_submesh)
        6. RANSAC plane fit + measurements (reuses _compute_measurements)
        7. Visualizations + PUSH score + clinical summary
        """
        from pipeline.reconstruction.arkit_mesh import (
            load_obj_bytes,
            crop_to_sphere,
            estimate_wound_center_world,
        )

        start_time = time.time()

        try:
            firestore.update_job_status(
                job_id, JobStatus.TIER1_PROCESSING, tier=1, progress=0.1
            )

            # 1. Parse OBJ mesh
            vertices, faces = load_obj_bytes(mesh_obj_bytes)
            if len(faces) < settings.lidar_mesh_min_faces:
                raise ValueError(
                    f"LiDAR mesh has too few faces ({len(faces)} < "
                    f"{settings.lidar_mesh_min_faces}). Move phone slowly "
                    f"around the wound for at least 2 seconds."
                )

            # 2. Decode the single best frame
            best_image = self._decode_frame(frame_bytes)
            firestore.update_job_status(
                job_id, JobStatus.TIER1_PROCESSING, tier=1, progress=0.2
            )

            # 3. SAM 2 segmentation on the frame
            point = self._parse_wound_point(wound_point, best_image.shape)
            wound_mask = self.segmenter.segment(best_image, point_prompt=point)
            firestore.update_job_status(
                job_id, JobStatus.TIER1_PROCESSING, tier=1, progress=0.4
            )

            # 4. Tissue classification (HSV-based, reused)
            from pipeline.segmentation.tissue import classify_tissue
            tissue_comp = classify_tissue(best_image, wound_mask)

            # 5. Find wound center in world space via ray-cast
            pose_c2w = np.array(pose["transform"], dtype=np.float64)
            wound_point_norm = None
            if wound_point:
                try:
                    parts = wound_point.split(",")
                    wound_point_norm = (float(parts[0]), float(parts[1]))
                except (ValueError, IndexError):
                    pass

            wound_center_world = estimate_wound_center_world(
                pose_c2w, intrinsics, wound_point_norm, vertices, faces
            )
            logger.info(
                "Wound center estimated at world position: %s",
                wound_center_world.tolist(),
            )

            # 6. Crop mesh to sphere around wound
            cropped_verts, cropped_faces = crop_to_sphere(
                vertices, faces, wound_center_world,
                radius_m=settings.lidar_crop_radius_m,
            )

            if len(cropped_faces) < 50:
                raise ValueError(
                    f"Cropped wound region has too few faces ({len(cropped_faces)}). "
                    f"Wound point may be incorrect or mesh too sparse in this region."
                )

            firestore.update_job_status(
                job_id, JobStatus.TIER1_PROCESSING, tier=1, progress=0.6
            )

            # 7. Extract wound submesh via mask projection (REUSED unchanged)
            wound_verts, wound_faces, boundary_points = self._extract_wound_submesh(
                cropped_verts, cropped_faces, wound_mask, intrinsics, pose
            )

            # 8. Compute measurements (REUSED unchanged)
            measurements = self._compute_measurements(
                wound_verts, wound_faces, boundary_points, tissue_comp
            )
            firestore.update_job_status(
                job_id, JobStatus.TIER1_PROCESSING, tier=1, progress=0.8
            )

            # 9. Visualizations
            from pipeline.visualization.annotated_image import generate_annotated_image
            from pipeline.visualization.wound_mask import generate_wound_mask_base64

            contours, _ = cv2.findContours(
                wound_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
            )
            contour = contours[0].reshape(-1, 2) if contours else np.array([])

            # Project the L/W endpoints from 3D world space into image pixels
            endpoints_2d = self._project_3d_endpoints_to_image(
                measurements.pop("_endpoints_3d", None),
                intrinsics, pose,
            )

            annotated = generate_annotated_image(
                best_image, contour,
                measurements["lengthMm"], measurements["widthMm"],
                length_endpoints=(
                    (endpoints_2d["length_p1"], endpoints_2d["length_p2"])
                    if endpoints_2d else None
                ),
                width_endpoints=(
                    (endpoints_2d["width_p1"], endpoints_2d["width_p2"])
                    if endpoints_2d else None
                ),
                wound_label="W1",
            )

            # Depth heatmap from cropped mesh (signed distance from plane)
            depth_heatmap = self._create_lidar_depth_heatmap(
                best_image, wound_mask, wound_verts, intrinsics, pose,
                measurements.get("maxDepthMm", 6.0),
            )

            mask_b64 = generate_wound_mask_base64(wound_mask)

            # 10. Export the cropped wound mesh as OBJ for the iOS 3D viewer
            from pipeline.reconstruction.tsdf import mesh_to_obj_bytes
            try:
                wound_mesh_o3d = trimesh.Trimesh(
                    vertices=wound_verts, faces=wound_faces, process=False
                )
                obj_bytes_out = wound_mesh_o3d.export(file_type="obj").encode("utf-8")
                obj_b64 = base64.b64encode(obj_bytes_out).decode("utf-8")
            except Exception as e:
                logger.warning("Failed to export wound mesh: %s", e)
                obj_b64 = None

            # 11. PUSH score + clinical summary (REUSED)
            from pipeline.measurement.push_score import compute_push_score
            push = compute_push_score(measurements["areaCm2"], tissue_comp)

            from pipeline.clinical.summary import generate_clinical_summary
            summary = generate_clinical_summary(measurements, tissue_comp, push)

            elapsed_ms = int((time.time() - start_time) * 1000)

            result = {
                "measurements": measurements,
                "annotatedImageBase64": annotated,
                "depthHeatmapBase64": depth_heatmap,
                "woundMaskBase64": mask_b64,
                "meshOBJData": obj_b64,
                "splatURL": None,
                "clinicalSummary": summary,
                "pushScore": push,
                "processingTimeMs": elapsed_ms,
                "quality": "gold",  # LiDAR is always gold-tier
            }

            # LiDAR pipeline is single-tier — write as final result directly
            firestore.update_job_final_result(job_id, result, measurement_delta=None)
            logger.info(
                "LiDAR pipeline complete for job %s in %dms",
                job_id, elapsed_ms,
            )

        except Exception as e:
            logger.error(
                "LiDAR pipeline failed for job %s: %s",
                job_id, e, exc_info=True,
            )
            firestore.update_job_status(job_id, JobStatus.FAILED, error=str(e))
            raise

    def _create_lidar_depth_heatmap(
        self,
        image: np.ndarray,
        wound_mask: np.ndarray,
        wound_vertices: np.ndarray,
        intrinsics: dict,
        pose: dict,
        max_depth_mm: float,
    ) -> str:
        """Generate depth heatmap by rasterizing per-pixel depth from wound vertices.

        Projects each wound vertex back into image space and rasterizes its
        signed distance from the wound plane.
        """
        from pipeline.visualization.depth_heatmap import generate_depth_heatmap

        h, w = image.shape[:2]
        depth_mm_map = np.zeros((h, w), dtype=np.float32)

        if len(wound_vertices) == 0:
            return generate_depth_heatmap(
                image, wound_mask, depth_mm_map, max_depth_mm=max(max_depth_mm, 1.0)
            )

        try:
            # Fit a plane to wound vertices to compute signed distances
            from pipeline.measurement.plane_fitter import fit_plane_svd
            centroid, normal = fit_plane_svd(wound_vertices)
            distances = np.abs((wound_vertices - centroid) @ normal) * 1000.0  # mm

            # Project vertices back to image space
            pose_c2w = np.array(pose["transform"], dtype=np.float64)
            w2c = np.linalg.inv(pose_c2w)
            R = w2c[:3, :3]
            t = w2c[:3, 3]
            cam_verts = (R @ wound_vertices.T).T + t  # (N, 3)

            depths = -cam_verts[:, 2]  # ARKit -Z forward
            valid = depths > 1e-6

            fx = intrinsics["fx"]
            fy = intrinsics["fy"]
            cx = intrinsics["cx"]
            cy = intrinsics["cy"]

            px = (fx * cam_verts[valid, 0] / -cam_verts[valid, 2] + cx).astype(int)
            py = (fy * cam_verts[valid, 1] / -cam_verts[valid, 2] + cy).astype(int)
            d = distances[valid]

            in_bounds = (px >= 0) & (px < w) & (py >= 0) & (py < h)
            depth_mm_map[py[in_bounds], px[in_bounds]] = d[in_bounds]

            # Restrict to wound mask
            depth_mm_map[wound_mask <= 127] = 0
        except Exception as e:
            logger.warning("Depth heatmap rasterization failed: %s", e)

        return generate_depth_heatmap(
            image, wound_mask, depth_mm_map,
            max_depth_mm=max(max_depth_mm, 1.0),
        )

    def process_scan(
        self,
        job_id: str,
        frames: list[bytes],
        poses: list[dict],
        intrinsics: dict,
        wound_point: str | None = None,
        use_woundambit: bool = False,
        generate_splat: bool = False,
    ) -> None:
        """Run the full tiered pipeline for a wound scan.

        Updates Firestore with results at each tier completion.
        """
        start_time = time.time()

        try:
            # ===== TIER 1: Fast results (5-8s) =====
            firestore.update_job_status(job_id, JobStatus.TIER1_PROCESSING, tier=1, progress=0.1)

            tier1_result = self._run_tier1(job_id, frames, poses, intrinsics, wound_point)
            tier1_time = int((time.time() - start_time) * 1000)
            tier1_result["processingTimeMs"] = tier1_time

            firestore.update_job_preliminary_result(job_id, tier1_result)
            logger.info("Tier 1 complete for job %s in %dms", job_id, tier1_time)

            # ===== TIER 2: COLMAP gold standard (30-60s) =====
            firestore.update_job_status(job_id, JobStatus.TIER2_PROCESSING, tier=2, progress=0.6)

            tier2_result, delta = self._run_tier2(
                job_id, frames, poses, intrinsics, tier1_result, wound_point
            )
            tier2_time = int((time.time() - start_time) * 1000)
            tier2_result["processingTimeMs"] = tier2_time

            firestore.update_job_final_result(job_id, tier2_result, delta)
            logger.info("Tier 2 complete for job %s in %dms", job_id, tier2_time)

            # ===== TIER 3: Gaussian Splatting (optional) =====
            if generate_splat:
                try:
                    self._run_tier3(job_id, frames, poses, intrinsics)
                except Exception as e:
                    logger.warning("Tier 3 (splat) failed for job %s: %s", job_id, e)

        except Exception as e:
            logger.error("Pipeline failed for job %s: %s", job_id, e, exc_info=True)
            firestore.update_job_status(job_id, JobStatus.FAILED, error=str(e))
            raise

    def _run_tier1(
        self,
        job_id: str,
        frames: list[bytes],
        poses: list[dict],
        intrinsics: dict,
        wound_point: str | None,
    ) -> dict:
        """Tier 1: Depth Pro + TSDF + SAM 2 + measurements."""
        # Decode frames
        images = [self._decode_frame(f) for f in frames]

        # Select best frontal frame for segmentation
        best_idx = self._select_best_frame(images)
        best_image = images[best_idx]

        # 1. SAM 2 segmentation
        point = self._parse_wound_point(wound_point, best_image.shape)
        wound_mask = self.segmenter.segment(best_image, point_prompt=point)

        # 2. Tissue classification
        from pipeline.segmentation.tissue import classify_tissue
        tissue_comp = classify_tissue(best_image, wound_mask)

        # 3. Depth estimation on all frames
        depth_maps = self.depth_estimator.estimate_depth_batch(images, intrinsics)

        # 4. TSDF fusion
        from pipeline.reconstruction.tsdf import fuse_depth_maps, mesh_to_numpy
        mesh = fuse_depth_maps(depth_maps, images, poses, intrinsics)
        vertices, faces = mesh_to_numpy(mesh)

        # 5. Extract wound submesh using mask projection
        wound_verts, wound_faces, boundary_points = self._extract_wound_submesh(
            vertices, faces, wound_mask, intrinsics, poses[best_idx]
        )

        # 6. Measurements
        measurements = self._compute_measurements(wound_verts, wound_faces, boundary_points, tissue_comp)

        # 7. Visualization
        from pipeline.visualization.annotated_image import generate_annotated_image
        from pipeline.visualization.depth_heatmap import generate_depth_heatmap
        from pipeline.visualization.wound_mask import generate_wound_mask_base64

        # Get wound contour for visualization
        contours, _ = cv2.findContours(wound_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contour = contours[0].reshape(-1, 2) if contours else np.array([])

        # Project the L/W endpoints from 3D world space into image pixels
        endpoints_2d = self._project_3d_endpoints_to_image(
            measurements.pop("_endpoints_3d", None),
            intrinsics, poses[best_idx],
        )

        annotated = generate_annotated_image(
            best_image, contour,
            measurements["lengthMm"], measurements["widthMm"],
            length_endpoints=(
                (endpoints_2d["length_p1"], endpoints_2d["length_p2"])
                if endpoints_2d else None
            ),
            width_endpoints=(
                (endpoints_2d["width_p1"], endpoints_2d["width_p2"])
                if endpoints_2d else None
            ),
            wound_label="W1",
        )

        depth_heatmap_image = self._create_depth_heatmap_from_mask(
            best_image, wound_mask, depth_maps[best_idx]
        )
        mask_b64 = generate_wound_mask_base64(wound_mask)

        # 8. PUSH score
        from pipeline.measurement.push_score import compute_push_score
        push = compute_push_score(measurements["areaCm2"], tissue_comp)

        # 9. Clinical summary
        from pipeline.clinical.summary import generate_clinical_summary
        summary = generate_clinical_summary(measurements, tissue_comp, push)

        return {
            "measurements": measurements,
            "annotatedImageBase64": annotated,
            "depthHeatmapBase64": depth_heatmap_image,
            "woundMaskBase64": mask_b64,
            "meshOBJData": None,
            "splatURL": None,
            "clinicalSummary": summary,
            "pushScore": push,
            "processingTimeMs": 0,  # Filled by caller
        }

    def _run_tier2(
        self,
        job_id: str,
        frames: list[bytes],
        poses: list[dict],
        intrinsics: dict,
        tier1_result: dict,
        wound_point: str | None,
    ) -> tuple[dict, dict | None]:
        """Tier 2: COLMAP MVS + refined measurements."""
        from pipeline.reconstruction.colmap import run_colmap_mvs
        from pipeline.reconstruction.tsdf import mesh_to_numpy, mesh_to_obj_bytes

        # Run COLMAP MVS
        mesh = run_colmap_mvs(frames, poses, intrinsics)
        vertices, faces = mesh_to_numpy(mesh)

        # Re-segment best frame for consistency
        images = [self._decode_frame(f) for f in frames]
        best_idx = self._select_best_frame(images)
        best_image = images[best_idx]

        point = self._parse_wound_point(wound_point, best_image.shape)
        wound_mask = self.segmenter.segment(best_image, point_prompt=point)

        # Extract wound submesh from COLMAP mesh
        wound_verts, wound_faces, boundary_points = self._extract_wound_submesh(
            vertices, faces, wound_mask, intrinsics, poses[best_idx]
        )

        # Refined measurements
        from pipeline.segmentation.tissue import classify_tissue
        tissue_comp = classify_tissue(best_image, wound_mask)
        measurements = self._compute_measurements(wound_verts, wound_faces, boundary_points, tissue_comp)

        # Export mesh as OBJ
        obj_bytes = mesh_to_obj_bytes(mesh)
        obj_b64 = base64.b64encode(obj_bytes).decode("utf-8")

        # Visualization (reuse mask, update annotated + heatmap)
        from pipeline.visualization.annotated_image import generate_annotated_image
        from pipeline.visualization.wound_mask import generate_wound_mask_base64

        contours, _ = cv2.findContours(wound_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contour = contours[0].reshape(-1, 2) if contours else np.array([])

        # Project the L/W endpoints from 3D world space into image pixels
        endpoints_2d = self._project_3d_endpoints_to_image(
            measurements.pop("_endpoints_3d", None),
            intrinsics, poses[best_idx],
        )

        annotated = generate_annotated_image(
            best_image, contour,
            measurements["lengthMm"], measurements["widthMm"],
            length_endpoints=(
                (endpoints_2d["length_p1"], endpoints_2d["length_p2"])
                if endpoints_2d else None
            ),
            width_endpoints=(
                (endpoints_2d["width_p1"], endpoints_2d["width_p2"])
                if endpoints_2d else None
            ),
            wound_label="W1",
        )
        mask_b64 = generate_wound_mask_base64(wound_mask)

        from pipeline.measurement.push_score import compute_push_score
        push = compute_push_score(measurements["areaCm2"], tissue_comp)

        from pipeline.clinical.summary import generate_clinical_summary
        summary = generate_clinical_summary(measurements, tissue_comp, push)

        result = {
            "measurements": measurements,
            "annotatedImageBase64": annotated,
            "depthHeatmapBase64": tier1_result.get("depthHeatmapBase64", ""),
            "woundMaskBase64": mask_b64,
            "meshOBJData": obj_b64,
            "splatURL": None,
            "clinicalSummary": summary,
            "pushScore": push,
            "processingTimeMs": 0,
        }

        # Compute measurement delta
        t1 = tier1_result.get("measurements", {})
        delta = self._compute_delta(t1, measurements)

        return result, delta

    def _run_tier3(
        self,
        job_id: str,
        frames: list[bytes],
        poses: list[dict],
        intrinsics: dict,
    ) -> None:
        """Tier 3: Gaussian Splatting (placeholder for future implementation)."""
        logger.info("Tier 3 (Gaussian Splatting) not yet implemented for job %s", job_id)

    def _decode_frame(self, frame_bytes: bytes) -> np.ndarray:
        """Decode JPEG bytes to RGB numpy array."""
        img = Image.open(io.BytesIO(frame_bytes)).convert("RGB")
        return np.array(img)

    def _select_best_frame(self, images: list[np.ndarray]) -> int:
        """Select the best frontal frame (most in-focus, center of sequence)."""
        # Use Laplacian variance as sharpness measure
        best_idx = len(images) // 2  # Default to middle frame
        best_sharpness = 0.0

        for i, img in enumerate(images):
            gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
            sharpness = cv2.Laplacian(gray, cv2.CV_64F).var()
            if sharpness > best_sharpness:
                best_sharpness = sharpness
                best_idx = i

        return best_idx

    def _parse_wound_point(
        self, wound_point: str | None, image_shape: tuple
    ) -> tuple[int, int] | None:
        """Parse wound_point string 'x,y' (normalized) to pixel coords."""
        if not wound_point:
            return None
        try:
            parts = wound_point.split(",")
            nx, ny = float(parts[0]), float(parts[1])
            h, w = image_shape[:2]
            return (int(nx * w), int(ny * h))
        except (ValueError, IndexError):
            return None

    def _extract_wound_submesh(
        self,
        vertices: np.ndarray,
        faces: np.ndarray,
        wound_mask: np.ndarray,
        intrinsics: dict,
        ref_pose: dict,
    ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """Project wound mask onto 3D mesh to extract wound submesh.

        Uses ray casting from the reference camera through mask pixels
        to find which mesh faces are inside the wound boundary.

        Returns:
            (wound_vertices, wound_faces, boundary_points_3d)
        """
        # Build trimesh for ray casting
        mesh = trimesh.Trimesh(vertices=vertices, faces=faces)

        # Camera parameters
        fx = intrinsics["fx"]
        fy = intrinsics["fy"]
        cx = intrinsics["cx"]
        cy = intrinsics["cy"]

        c2w = np.array(ref_pose["transform"], dtype=np.float64)
        camera_pos = c2w[:3, 3]
        R = c2w[:3, :3]

        # Sample wound mask pixels (subsample for speed)
        mask_ys, mask_xs = np.where(wound_mask > 127)
        if len(mask_xs) == 0:
            return vertices[:0], faces[:0], np.zeros((0, 3))

        # Subsample to max 2000 rays
        step = max(1, len(mask_xs) // 2000)
        mask_xs = mask_xs[::step]
        mask_ys = mask_ys[::step]

        # Scale pixel coords if mask size differs from intrinsics
        h_mask, w_mask = wound_mask.shape[:2]
        scale_x = intrinsics["width"] / w_mask
        scale_y = intrinsics["height"] / h_mask
        xs = mask_xs.astype(float) * scale_x
        ys = mask_ys.astype(float) * scale_y

        # Build ray directions in camera space, then transform to world
        dirs_cam = np.column_stack([
            (xs - cx) / fx,
            (ys - cy) / fy,
            np.ones(len(xs)),
        ])
        # ARKit: Z points toward viewer, so negate for forward direction
        dirs_cam[:, 2] = -dirs_cam[:, 2]
        dirs_world = (R @ dirs_cam.T).T
        dirs_world /= np.linalg.norm(dirs_world, axis=1, keepdims=True)

        # Ray cast
        origins = np.tile(camera_pos, (len(dirs_world), 1))
        locations, index_ray, index_tri = mesh.ray.intersects_location(
            ray_origins=origins,
            ray_directions=dirs_world,
        )

        if len(index_tri) == 0:
            return vertices[:0], faces[:0], np.zeros((0, 3))

        # Get unique wound faces
        wound_face_mask = np.zeros(len(faces), dtype=bool)
        wound_face_mask[np.unique(index_tri)] = True

        # Extract wound vertices
        wound_face_indices = np.where(wound_face_mask)[0]
        wound_faces_subset = faces[wound_face_indices]
        unique_verts = np.unique(wound_faces_subset.ravel())
        wound_vertices = vertices[unique_verts]

        # Remap face indices
        vert_map = np.full(len(vertices), -1, dtype=int)
        vert_map[unique_verts] = np.arange(len(unique_verts))
        remapped_faces = vert_map[wound_faces_subset]

        # Extract boundary points (vertices on the wound perimeter)
        boundary_points = self._extract_boundary_vertices(
            wound_vertices, remapped_faces
        )

        return wound_vertices, remapped_faces, boundary_points

    def _extract_boundary_vertices(
        self,
        vertices: np.ndarray,
        faces: np.ndarray,
    ) -> np.ndarray:
        """Extract boundary vertices from a mesh (edges shared by only one face)."""
        from collections import Counter

        edge_count = Counter()
        for face in faces:
            for i in range(3):
                edge = tuple(sorted([face[i], face[(i + 1) % 3]]))
                edge_count[edge] += 1

        boundary_vert_set = set()
        for edge, count in edge_count.items():
            if count == 1:
                boundary_vert_set.add(edge[0])
                boundary_vert_set.add(edge[1])

        if not boundary_vert_set:
            return vertices[:0]

        boundary_indices = sorted(boundary_vert_set)
        return vertices[boundary_indices]

    def _compute_measurements(
        self,
        wound_vertices: np.ndarray,
        wound_faces: np.ndarray,
        boundary_points: np.ndarray,
        tissue_comp: dict,
    ) -> dict:
        """Compute all wound measurements from the mesh.

        Also stores the 3D endpoints of the L and W axes under the key
        ``_endpoints_3d`` so the caller can project them into the annotated image.
        The underscore prefix marks this as an internal field that the JSON
        serializer should strip before returning to the iOS client.
        """
        from pipeline.measurement.plane_fitter import fit_plane_ransac
        from pipeline.measurement.surface_area import compute_surface_area_cm2
        from pipeline.measurement.depth_calc import compute_max_depth_mm, compute_avg_depth_mm
        from pipeline.measurement.volume import compute_volume_ml
        from pipeline.measurement.dimensions import (
            compute_length_width_with_endpoints,
            compute_perimeter_mm,
        )

        # Handle empty mesh
        if len(wound_vertices) < 3 or len(boundary_points) < 3:
            return {
                "areaCm2": 0.0, "maxDepthMm": 0.0, "avgDepthMm": 0.0,
                "volumeMl": 0.0, "lengthMm": 0.0, "widthMm": 0.0,
                "perimeterMm": 0.0, "circumferenceCm": 0.0,
                "underminingMm": None, "tunnelingMm": None,
                "_endpoints_3d": None,
            }

        # Fit reference plane
        centroid, normal, _ = fit_plane_ransac(boundary_points)

        # Surface area
        area_cm2 = compute_surface_area_cm2(wound_vertices, wound_faces)

        # Depth
        max_depth = compute_max_depth_mm(wound_vertices, centroid, normal)
        avg_depth = compute_avg_depth_mm(wound_vertices, centroid, normal)

        # Volume
        volume = compute_volume_ml(wound_vertices, wound_faces, centroid, normal)

        # Length, width, perimeter (now also returning endpoint indices)
        (
            length, width,
            l_p1_idx, l_p2_idx,
            w_p1_idx, w_p2_idx,
        ) = compute_length_width_with_endpoints(boundary_points, centroid, normal)
        perimeter = compute_perimeter_mm(boundary_points)

        # Capture the four 3D endpoints (length L1, L2 and width W1, W2)
        endpoints_3d = None
        try:
            endpoints_3d = {
                "length_p1": boundary_points[l_p1_idx],
                "length_p2": boundary_points[l_p2_idx],
                "width_p1": boundary_points[w_p1_idx],
                "width_p2": boundary_points[w_p2_idx],
            }
        except IndexError:
            pass

        return {
            "areaCm2": round(area_cm2, 2),
            "maxDepthMm": round(max_depth, 1),
            "avgDepthMm": round(avg_depth, 1),
            "volumeMl": round(volume, 2),
            "lengthMm": round(length, 1),
            "widthMm": round(width, 1),
            "perimeterMm": round(perimeter, 1),
            "circumferenceCm": round(perimeter / 10.0, 2),  # mm → cm
            "underminingMm": None,
            "tunnelingMm": None,
            "_endpoints_3d": endpoints_3d,
        }

    def _project_3d_endpoints_to_image(
        self,
        endpoints_3d: dict | None,
        intrinsics: dict,
        pose: dict,
    ) -> dict | None:
        """Project the 3D L/W endpoints back into the reference image's pixel space.

        Returns a dict with keys ``length_p1``, ``length_p2``, ``width_p1``,
        ``width_p2`` mapped to (x, y) pixel coordinate numpy arrays, or None
        if endpoints unavailable.
        """
        if endpoints_3d is None:
            return None

        try:
            fx = intrinsics["fx"]
            fy = intrinsics["fy"]
            cx = intrinsics["cx"]
            cy = intrinsics["cy"]

            pose_c2w = np.array(pose["transform"], dtype=np.float64)
            w2c = np.linalg.inv(pose_c2w)
            R = w2c[:3, :3]
            t = w2c[:3, 3]

            def project(point_world: np.ndarray) -> np.ndarray:
                pw = np.asarray(point_world, dtype=np.float64)
                cam = R @ pw + t  # (3,)
                # ARKit -Z forward: depth = -cam_z
                z = -cam[2]
                if z < 1e-6:
                    return np.array([0.0, 0.0])
                u = fx * cam[0] / -cam[2] + cx
                v = fy * cam[1] / -cam[2] + cy
                return np.array([u, v])

            return {
                "length_p1": project(endpoints_3d["length_p1"]),
                "length_p2": project(endpoints_3d["length_p2"]),
                "width_p1": project(endpoints_3d["width_p1"]),
                "width_p2": project(endpoints_3d["width_p2"]),
            }
        except (KeyError, ValueError, np.linalg.LinAlgError):
            return None

    def _create_depth_heatmap_from_mask(
        self,
        image: np.ndarray,
        wound_mask: np.ndarray,
        depth_map: np.ndarray,
    ) -> str:
        """Create depth heatmap using Depth Pro output."""
        from pipeline.visualization.depth_heatmap import generate_depth_heatmap

        # Resize depth map to match image if needed
        if depth_map.shape[:2] != image.shape[:2]:
            depth_map = cv2.resize(depth_map, (image.shape[1], image.shape[0]))

        # Convert depth to mm for wound region
        wound_pixels = wound_mask > 127
        if wound_pixels.any():
            wound_depths = depth_map[wound_pixels]
            median_depth = np.median(wound_depths)
            # Relative depth from surface (mm)
            depth_mm = np.clip((depth_map - median_depth) * 1000, 0, None)
            depth_mm[~wound_pixels] = 0
        else:
            depth_mm = np.zeros_like(depth_map)

        max_depth = depth_mm[wound_pixels].max() if wound_pixels.any() else 6.0
        return generate_depth_heatmap(image, wound_mask, depth_mm, max_depth_mm=max(max_depth, 1.0))

    def _compute_delta(self, tier1_measurements: dict, tier2_measurements: dict) -> dict | None:
        """Compute measurement difference between tiers."""
        t1_area = tier1_measurements.get("areaCm2", 0)
        t2_area = tier2_measurements.get("areaCm2", 0)
        t1_depth = tier1_measurements.get("maxDepthMm", 0)
        t2_depth = tier2_measurements.get("maxDepthMm", 0)

        if t1_area == 0 and t2_area == 0:
            return None

        area_diff = abs(t2_area - t1_area) / max(t1_area, 0.01) * 100
        depth_diff = abs(t2_depth - t1_depth) / max(t1_depth, 0.01) * 100

        return {
            "areaDiffPercent": round(area_diff, 1),
            "depthDiffPercent": round(depth_diff, 1),
            "note": f"COLMAP refined measurements differ by {area_diff:.0f}% (area) and {depth_diff:.0f}% (depth) from initial estimate",
        }


def get_orchestrator() -> PipelineOrchestrator:
    """Get or create the singleton pipeline orchestrator."""
    global _instance
    if _instance is None:
        _instance = PipelineOrchestrator()
    return _instance
