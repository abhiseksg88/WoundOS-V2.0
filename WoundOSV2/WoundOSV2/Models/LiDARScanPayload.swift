import Foundation
import simd

/// Payload for the LiDAR-native capture path.
///
/// On LiDAR-equipped devices (iPhone 12 Pro+, iPad Pro), instead of uploading
/// 30 multi-view JPEG frames for backend photogrammetry, we upload:
/// - A single best frontal frame (sharpest, most centered)
/// - The ARKit scene reconstruction mesh as an OBJ file (already in world coords)
/// - Optional 16-bit depth PNG from `ARFrame.sceneDepth.depthMap`
///
/// Total payload size: ~5 MB (vs ~120 MB for multiview).
/// Backend processing time: ~3-5 seconds (vs 30-60 seconds for COLMAP MVS).
struct LiDARScanPayload {
    /// Best single frame selected during capture (sharpest + most frontal).
    let bestFrame: SelectedFrame

    /// Wavefront OBJ bytes serialized from collected ARMeshAnchor objects.
    /// Already cropped on-device to a sphere around the wound region.
    let meshOBJData: Data

    /// Optional 16-bit grayscale PNG of `ARFrame.sceneDepth.depthMap`,
    /// values in millimeters (Float32 meters × 1000 → UInt16). Used by the
    /// backend to refine per-pixel depth in the wound region. Optional in v1.
    let depthPNG: Data?

    /// Number of ARMeshAnchor objects merged into the OBJ. Diagnostic only.
    let anchorCount: Int

    /// Bounding box of the cropped mesh in meters (for telemetry).
    let worldBoundsMeters: SIMD3<Float>
}
