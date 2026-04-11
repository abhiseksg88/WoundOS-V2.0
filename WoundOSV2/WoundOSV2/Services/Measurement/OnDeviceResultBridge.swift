import Foundation
import UIKit
import CoreGraphics

/// Bridges an on-device `PrimaryMeasurement` + `WoundCaptureSnapshot` into the
/// existing `ServerResponse` shape so the rest of the app (`ResultsView`,
/// `ScanStore`, PDF report) doesn't have to know about the new path.
///
/// This is a temporary adapter until the rest of the app is migrated to the
/// `PrimaryMeasurement` model directly.
enum OnDeviceResultBridge {

    /// Build a `ServerResponse` carrying the on-device results, with the polygon
    /// + L/W markers rendered onto the captured RGB frame as the annotated image.
    static func makeResponse(
        snapshot: WoundCaptureSnapshot,
        measurement: PrimaryMeasurement
    ) -> ServerResponse {
        let annotated = renderAnnotatedImage(
            base: snapshot.rgbImage,
            polygonPixels: measurement.boundary2DPixels,
            markerPixels: measurement.markerEndpointsPixels,
            imageWidth: snapshot.imageWidth,
            imageHeight: snapshot.imageHeight
        )

        let annotatedBase64 = annotated.jpegData(compressionQuality: 0.9)?
            .base64EncodedString() ?? ""

        let mask = renderPolygonMask(
            polygonPixels: measurement.boundary2DPixels,
            imageWidth: snapshot.imageWidth,
            imageHeight: snapshot.imageHeight
        )
        let maskBase64 = mask?.pngData()?.base64EncodedString() ?? ""

        return ServerResponse(
            measurements: measurement.asWoundMeasurement,
            annotatedImageBase64: annotatedBase64,
            depthHeatmapBase64: "",
            woundMaskBase64: maskBase64,
            meshOBJData: snapshot.meshOBJData,
            splatURL: nil,
            clinicalSummary: defaultClinicalSummary(for: measurement),
            pushScore: measurement.pushScore,
            processingTimeMs: measurement.processingTimeMs,
            quality: .gold
        )
    }

    // MARK: - Annotated image rendering

    /// Draw the nurse's polygon (in image-pixel space) onto the captured frame
    /// and overlay the L/W cross markers. Returns the rendered UIImage.
    static func renderAnnotatedImage(
        base: UIImage,
        polygonPixels: [CGPoint],
        markerPixels: [CGPoint],
        imageWidth: Int,
        imageHeight: Int
    ) -> UIImage {
        let size = CGSize(width: imageWidth, height: imageHeight)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Draw the base image stretched to full pixel canvas
            base.draw(in: CGRect(origin: .zero, size: size))

            let cg = ctx.cgContext

            // Polygon fill (semi-transparent green)
            if polygonPixels.count >= 3 {
                cg.setFillColor(UIColor.systemGreen.withAlphaComponent(0.20).cgColor)
                cg.beginPath()
                cg.move(to: polygonPixels[0])
                for p in polygonPixels.dropFirst() {
                    cg.addLine(to: p)
                }
                cg.closePath()
                cg.fillPath()

                // Polygon stroke (solid green)
                cg.setStrokeColor(UIColor.systemGreen.cgColor)
                cg.setLineWidth(CGFloat(max(imageWidth, imageHeight)) * 0.003)
                cg.beginPath()
                cg.move(to: polygonPixels[0])
                for p in polygonPixels.dropFirst() {
                    cg.addLine(to: p)
                }
                cg.closePath()
                cg.strokePath()
            }

            // L/W markers — expect [lengthA, lengthB, widthA, widthB]
            guard markerPixels.count == 4 else { return }
            let lineWidth = CGFloat(max(imageWidth, imageHeight)) * 0.003

            // Length axis (cyan)
            cg.setStrokeColor(UIColor.systemTeal.cgColor)
            cg.setLineWidth(lineWidth)
            cg.beginPath()
            cg.move(to: markerPixels[0])
            cg.addLine(to: markerPixels[1])
            cg.strokePath()

            // Width axis (magenta)
            cg.setStrokeColor(UIColor.systemPink.cgColor)
            cg.beginPath()
            cg.move(to: markerPixels[2])
            cg.addLine(to: markerPixels[3])
            cg.strokePath()

            // Endpoint dots
            let r = CGFloat(max(imageWidth, imageHeight)) * 0.006
            for (i, p) in markerPixels.enumerated() {
                let color: UIColor = i < 2 ? .systemTeal : .systemPink
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
        }
    }

    /// Render a binary mask (white polygon on black background) at the
    /// snapshot's full pixel resolution.
    static func renderPolygonMask(
        polygonPixels: [CGPoint],
        imageWidth: Int,
        imageHeight: Int
    ) -> UIImage? {
        guard polygonPixels.count >= 3, imageWidth > 0, imageHeight > 0 else { return nil }
        let size = CGSize(width: imageWidth, height: imageHeight)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setFillColor(UIColor.white.cgColor)
            cg.beginPath()
            cg.move(to: polygonPixels[0])
            for p in polygonPixels.dropFirst() {
                cg.addLine(to: p)
            }
            cg.closePath()
            cg.fillPath()
        }
    }

    // MARK: - Default clinical summary

    /// A short human-readable summary the user sees on the results screen until
    /// the (still-async) Claude summary lands from the shadow validation worker.
    static func defaultClinicalSummary(for m: PrimaryMeasurement) -> String {
        let l = String(format: "%.1f", m.lengthMm / 10.0)
        let w = String(format: "%.1f", m.widthMm / 10.0)
        let area = String(format: "%.1f", m.areaCm2)
        if m.maxDepthMm > 0 {
            let d = String(format: "%.1f", m.maxDepthMm)
            return "Wound measured on-device: \(l)×\(w) cm, area \(area) cm², max depth \(d) mm."
        }
        return "Wound measured on-device: \(l)×\(w) cm, area \(area) cm²."
    }
}
