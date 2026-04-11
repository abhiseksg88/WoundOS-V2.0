import Foundation
import CoreVideo
import CoreImage
import UIKit
import Accelerate

/// Encodes `ARFrame.sceneDepth.depthMap` (Float32 meters) as a 16-bit grayscale PNG
/// where pixel values represent depth in millimeters (0-65535).
///
/// The backend can use this for sub-millimeter depth refinement in the wound
/// region, complementing the coarser ARKit scene reconstruction mesh.
enum DepthMapExporter {

    /// Encode a CVPixelBuffer of `kCVPixelFormatType_DepthFloat32` to 16-bit PNG.
    ///
    /// - Parameters:
    ///   - depthMap: ARFrame.sceneDepth.depthMap (Float32 meters per pixel).
    ///   - maxMeters: clamp range; values above this saturate to UInt16.max.
    /// - Returns: PNG bytes, or nil on encoding failure.
    static func encodePNG16(depthMap: CVPixelBuffer, maxMeters: Float = 5.0) -> Data? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        // Convert Float32 meters → UInt16 millimeters
        var uint16Buffer = [UInt16](repeating: 0, count: width * height)
        let maxMM: Float = maxMeters * 1000.0
        let clampValue: Float = Float(UInt16.max)

        for y in 0..<height {
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let meters = rowPtr[x]
                if meters.isNaN || meters.isInfinite || meters <= 0 {
                    uint16Buffer[y * width + x] = 0
                } else {
                    let mm = min(meters * 1000.0, maxMM)
                    let clamped = min(max(mm, 0), clampValue)
                    uint16Buffer[y * width + x] = UInt16(clamped)
                }
            }
        }

        // Build a CGImage from the UInt16 buffer
        let bitsPerComponent = 16
        let bitsPerPixel = 16
        let bytesPerRowOut = width * 2
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGImageByteOrderInfo.order16Little.rawValue)

        let dataSize = uint16Buffer.count * MemoryLayout<UInt16>.size
        guard let provider = CGDataProvider(data: Data(bytes: uint16Buffer, count: dataSize) as CFData) else {
            return nil
        }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRowOut,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        // Encode as PNG using ImageIO
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return mutableData as Data
    }
}
