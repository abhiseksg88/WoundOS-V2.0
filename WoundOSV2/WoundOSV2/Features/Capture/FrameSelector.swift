import Foundation
import ARKit
import Accelerate

final class FrameSelector {
    private var lastSelectedPose: CameraPose?
    private var firstBrightness: Float?
    private var selectedCount: Int = 0
    private var elevations: [Float] = []

    var needsElevationChange: Bool {
        guard elevations.count >= 20 else { return false }
        guard let minE = elevations.min(), let maxE = elevations.max() else { return false }
        return (maxE - minE) < 0.03
    }

    func shouldSelect(frame: ARFrame, pose: CameraPose) -> Bool {
        guard frame.camera.trackingState == .normal else { return false }
        guard selectedCount < ServerConfig.maxFrames else { return false }

        let cameraY = frame.camera.transform.columns.3.y
        elevations.append(cameraY)

        // First frame always selected
        if lastSelectedPose == nil {
            accept(pose: pose, frame: frame)
            return true
        }

        // Check parallax
        guard hasEnoughParallax(current: frame.camera, lastPose: lastSelectedPose!) else {
            return false
        }

        // Check sharpness
        guard isSharp(pixelBuffer: frame.capturedImage) else {
            return false
        }

        // Check exposure consistency
        guard isExposureConsistent(pixelBuffer: frame.capturedImage) else {
            return false
        }

        accept(pose: pose, frame: frame)
        return true
    }

    var totalArcCoverage: Float {
        guard elevations.count > 1 else { return 0 }
        // Simplified: return estimated arc based on frame count
        return Float(selectedCount) * ServerConfig.minParallaxDegrees
    }

    private func accept(pose: CameraPose, frame: ARFrame) {
        lastSelectedPose = pose
        selectedCount += 1

        if firstBrightness == nil {
            firstBrightness = meanBrightness(pixelBuffer: frame.capturedImage)
        }
    }

    // MARK: - Parallax Check

    private func hasEnoughParallax(current: ARCamera, lastPose: CameraPose) -> Bool {
        let currentForward = simd_float3(
            -current.transform.columns.2.x,
            -current.transform.columns.2.y,
            -current.transform.columns.2.z
        )

        let lastTransform = lastPose.transform
        guard lastTransform.count == 4, lastTransform[0].count == 4 else { return true }
        let lastForward = simd_float3(
            -lastTransform[0][2],
            -lastTransform[1][2],
            -lastTransform[2][2]
        )

        let dotProduct = simd_dot(simd_normalize(currentForward), simd_normalize(lastForward))
        let clampedDot = min(max(dotProduct, -1.0), 1.0)
        let angleDegrees = acos(clampedDot) * 180.0 / .pi

        return angleDegrees >= ServerConfig.minParallaxDegrees
    }

    // MARK: - Sharpness via Laplacian Variance (Accelerate)

    private func isSharp(pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Work on center 60% crop
        let cropX = Int(Double(width) * 0.2)
        let cropY = Int(Double(height) * 0.2)
        let cropW = Int(Double(width) * 0.6)
        let cropH = Int(Double(height) * 0.6)

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return true }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        // Extract grayscale center crop (Y plane of YCbCr)
        var grayPixels = [Float](repeating: 0, count: cropW * cropH)
        for row in 0..<cropH {
            let srcRow = baseAddress.advanced(by: (cropY + row) * bytesPerRow + cropX)
            for col in 0..<cropW {
                grayPixels[row * cropW + col] = Float(srcRow.load(fromByteOffset: col, as: UInt8.self))
            }
        }

        // Compute Laplacian (simplified: sum of second derivatives)
        var variance: Float = 0
        let count = cropW * cropH
        guard count > 4 else { return true }

        var laplacianValues = [Float](repeating: 0, count: count)
        for row in 1..<(cropH - 1) {
            for col in 1..<(cropW - 1) {
                let idx = row * cropW + col
                let lap = -4 * grayPixels[idx]
                    + grayPixels[idx - 1]
                    + grayPixels[idx + 1]
                    + grayPixels[idx - cropW]
                    + grayPixels[idx + cropW]
                laplacianValues[idx] = lap
            }
        }

        // Compute variance using vDSP
        var mean: Float = 0
        var meanSq: Float = 0
        vDSP_meanv(laplacianValues, 1, &mean, vDSP_Length(count))
        vDSP_measqv(laplacianValues, 1, &meanSq, vDSP_Length(count))
        variance = meanSq - mean * mean

        return variance >= ServerConfig.minSharpnessVariance
    }

    // MARK: - Exposure Consistency

    private func isExposureConsistent(pixelBuffer: CVPixelBuffer) -> Bool {
        guard let first = firstBrightness else { return true }
        let current = meanBrightness(pixelBuffer: pixelBuffer)
        let ratio = abs(current - first) / max(first, 1)
        return ratio <= ServerConfig.exposureTolerance
    }

    private func meanBrightness(pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 128 }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        // Sample every 8th pixel for speed
        var sum: Float = 0
        var count: Float = 0
        for row in stride(from: 0, to: height, by: 8) {
            let rowPtr = baseAddress.advanced(by: row * bytesPerRow)
            for col in stride(from: 0, to: width, by: 8) {
                sum += Float(rowPtr.load(fromByteOffset: col, as: UInt8.self))
                count += 1
            }
        }
        return count > 0 ? sum / count : 128
    }
}
