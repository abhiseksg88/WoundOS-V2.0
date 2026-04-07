import UIKit
import CoreImage
import Accelerate

enum ImageProcessing {
    static func convertToGrayscale(_ image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let filter = CIFilter(name: "CIColorMonochrome")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIColor(color: .gray), forKey: "inputColor")
        filter?.setValue(1.0, forKey: "inputIntensity")

        guard let outputImage = filter?.outputImage else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func generateDepthHeatmap(from depthBuffer: [Float], width: Int, height: Int, minDepth: Float = 0, maxDepth: Float = 6) -> UIImage? {
        let pixelCount = width * height
        guard depthBuffer.count >= pixelCount else { return nil }

        var pixels = [UInt8](repeating: 0, count: pixelCount * 4) // RGBA

        for i in 0..<pixelCount {
            let depth = depthBuffer[i]
            let normalized = min(max((depth - minDepth) / (maxDepth - minDepth), 0), 1)

            // Green (shallow) → Yellow → Red (deep)
            let r: UInt8
            let g: UInt8
            let b: UInt8

            if normalized < 0.5 {
                let t = normalized * 2
                r = UInt8(t * 255)
                g = 255
                b = 0
            } else {
                let t = (normalized - 0.5) * 2
                r = 255
                g = UInt8((1 - t) * 255)
                b = 0
            }

            pixels[i * 4] = r
            pixels[i * 4 + 1] = g
            pixels[i * 4 + 2] = b
            pixels[i * 4 + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func extractDepthFromCVPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }

        var depths = [Float](repeating: 0, count: width * height)

        for row in 0..<height {
            let rowPtr = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for col in 0..<width {
                depths[row * width + col] = rowPtr[col]
            }
        }

        return depths
    }
}
