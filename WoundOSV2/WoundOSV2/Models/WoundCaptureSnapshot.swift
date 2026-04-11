import Foundation
import simd
import UIKit

/// A frozen capture moment used as input to the on-device measurement pipeline.
///
/// Unlike the multi-view pan flow, the clinical path captures **one moment**:
/// the nurse aims, taps the shutter, and we freeze everything we need to make
/// a measurement entirely on-device with zero network calls.
struct WoundCaptureSnapshot {
    /// JPEG-compressed RGB frame at the moment the shutter was tapped.
    let rgbJpegData: Data

    /// Display image (UIImage) ready for the boundary edit canvas.
    let rgbImage: UIImage

    /// Image dimensions in pixels (full resolution).
    let imageWidth: Int
    let imageHeight: Int

    /// Camera intrinsics at the captured frame.
    let intrinsics: CameraIntrinsics

    /// Camera pose at the captured frame.
    let pose: CameraPose

    /// Wavefront OBJ-encoded ARMeshAnchor mesh, sphere-cropped around the wound.
    /// Used as the geometry for ray-casting and plane fitting.
    let meshOBJData: Data?

    /// Optional 16-bit depth PNG (millimeters). Only present on LiDAR devices.
    let depthPNGData: Data?

    /// Approximate distance from camera to detected plane (meters), captured at shutter time.
    let cameraToWoundDistanceMeters: Float?

    /// Telemetry: anchor count, world bounds, etc.
    let meshAnchorCount: Int
    let worldBoundsMeters: SIMD3<Float>
    let capturedAt: Date
}

extension WoundCaptureSnapshot {
    /// Build a snapshot from the LiDAR-mode capture payload produced by `ARSessionManager.finalizeLiDARPayload`.
    /// Returns nil if the JPEG can't be decoded.
    init?(lidarPayload: LiDARScanPayload, cameraToWoundDistanceMeters: Float?) {
        guard let image = UIImage(data: lidarPayload.bestFrame.jpegData) else {
            return nil
        }
        self.rgbJpegData = lidarPayload.bestFrame.jpegData
        self.rgbImage = image
        self.imageWidth = lidarPayload.bestFrame.intrinsics.width
        self.imageHeight = lidarPayload.bestFrame.intrinsics.height
        self.intrinsics = lidarPayload.bestFrame.intrinsics
        self.pose = lidarPayload.bestFrame.pose
        self.meshOBJData = lidarPayload.meshOBJData
        self.depthPNGData = lidarPayload.depthPNG
        self.cameraToWoundDistanceMeters = cameraToWoundDistanceMeters
        self.meshAnchorCount = lidarPayload.anchorCount
        self.worldBoundsMeters = lidarPayload.worldBoundsMeters
        self.capturedAt = Date()
    }

    /// Build a snapshot from a multi-view capture (no LiDAR mesh available).
    /// This is the fallback path on non-LiDAR devices.
    init?(bestFrame: SelectedFrame, cameraToWoundDistanceMeters: Float) {
        guard let image = UIImage(data: bestFrame.jpegData) else { return nil }
        self.rgbJpegData = bestFrame.jpegData
        self.rgbImage = image
        self.imageWidth = bestFrame.intrinsics.width
        self.imageHeight = bestFrame.intrinsics.height
        self.intrinsics = bestFrame.intrinsics
        self.pose = bestFrame.pose
        self.meshOBJData = nil
        self.depthPNGData = nil
        self.cameraToWoundDistanceMeters = cameraToWoundDistanceMeters
        self.meshAnchorCount = 0
        self.worldBoundsMeters = .zero
        self.capturedAt = Date()
    }
}
