import UIKit
import PDFKit

final class PDFReportGenerator {
    struct ReportData {
        let patient: Patient?
        let scan: WoundScan
        let measurements: WoundMeasurement
        let pushScore: PUSHScore?
        let clinicalSummary: String?
        let annotatedImage: UIImage?
        let depthHeatmap: UIImage?
        let meshSnapshot: UIImage?
    }

    static func generateReport(data: ReportData) -> URL? {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - 2 * margin

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let scanDir = ScanStore.scanDirectory(for: data.scan.id)
        let pdfURL = scanDir.appendingPathComponent("wound_report.pdf")

        do {
            try renderer.writePDF(to: pdfURL) { context in
                // PAGE 1
                context.beginPage()
                var yOffset: CGFloat = margin

                // Header
                yOffset = drawHeader(at: yOffset, width: contentWidth, margin: margin)

                // Patient Info
                if let patient = data.patient {
                    yOffset = drawPatientInfo(patient: patient, scan: data.scan, at: yOffset, width: contentWidth, margin: margin)
                }

                // Images row
                yOffset = drawImages(annotated: data.annotatedImage, heatmap: data.depthHeatmap, at: yOffset, width: contentWidth, margin: margin)

                // Measurements table
                yOffset = drawMeasurementsTable(measurements: data.measurements, at: yOffset, width: contentWidth, margin: margin)

                // PUSH Score
                if let pushScore = data.pushScore {
                    yOffset = drawPUSHScore(score: pushScore, at: yOffset, width: contentWidth, margin: margin)
                }

                // Footer
                drawFooter(pageWidth: pageWidth, pageHeight: pageHeight, margin: margin, pageNumber: 1)

                // PAGE 2 (if needed)
                if data.clinicalSummary != nil || data.meshSnapshot != nil {
                    context.beginPage()
                    yOffset = margin

                    // Clinical Summary
                    if let summary = data.clinicalSummary {
                        yOffset = drawClinicalSummary(text: summary, at: yOffset, width: contentWidth, margin: margin)
                    }

                    // 3D Snapshot
                    if let snapshot = data.meshSnapshot {
                        yOffset = drawSnapshot(image: snapshot, at: yOffset, width: contentWidth, margin: margin)
                    }

                    // Signature line
                    yOffset = drawSignatureLine(at: max(yOffset, pageHeight - 150), width: contentWidth, margin: margin)

                    drawFooter(pageWidth: pageWidth, pageHeight: pageHeight, margin: margin, pageNumber: 2)
                }
            }
            return pdfURL
        } catch {
            print("PDF generation failed: \(error)")
            return nil
        }
    }

    // MARK: - Drawing Helpers

    private static func drawHeader(at y: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var yPos = y

        // Logo placeholder
        let logoRect = CGRect(x: margin, y: yPos, width: 180, height: 36)
        UIColor.systemTeal.setFill()
        UIBezierPath(roundedRect: logoRect, cornerRadius: 6).fill()

        let logoAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        "CarePlix WoundOS".draw(at: CGPoint(x: margin + 12, y: yPos + 8), withAttributes: logoAttrs)

        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)
        let dateSize = dateStr.size(withAttributes: dateAttrs)
        dateStr.draw(at: CGPoint(x: margin + width - dateSize.width, y: yPos + 12), withAttributes: dateAttrs)

        yPos += 50

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        "Wound Assessment Report".draw(at: CGPoint(x: margin, y: yPos), withAttributes: titleAttrs)
        yPos += 36

        // Divider
        UIColor.systemTeal.setStroke()
        let divider = UIBezierPath()
        divider.move(to: CGPoint(x: margin, y: yPos))
        divider.addLine(to: CGPoint(x: margin + width, y: yPos))
        divider.lineWidth = 2
        divider.stroke()
        yPos += 16

        return yPos
    }

    private static func drawPatientInfo(patient: Patient, scan: WoundScan, at y: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var yPos = y

        let sectionTitle: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor.black
        ]

        "Patient Information".draw(at: CGPoint(x: margin, y: yPos), withAttributes: sectionTitle)
        yPos += 22

        let fields: [(String, String)] = [
            ("Name", patient.fullName),
            ("DOB", patient.dateOfBirth.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "N/A"),
            ("MRN", patient.mrn ?? "N/A"),
            ("Facility", patient.facilityName ?? "N/A"),
            ("Room", patient.roomNumber ?? "N/A"),
            ("Wound Location", scan.bodyLocation.displayName),
            ("Wound Type", scan.woundType.displayName),
            ("Scan Date", DateFormatter.localizedString(from: scan.capturedAt, dateStyle: .medium, timeStyle: .short)),
        ]

        let colWidth = width / 2
        for (index, field) in fields.enumerated() {
            let col = CGFloat(index % 2)
            if index % 2 == 0 && index > 0 { yPos += 18 }

            let x = margin + col * colWidth
            "\(field.0):".draw(at: CGPoint(x: x, y: yPos), withAttributes: labelAttrs)
            field.1.draw(at: CGPoint(x: x + 80, y: yPos), withAttributes: valueAttrs)
        }
        yPos += 30

        return yPos
    }

    private static func drawImages(annotated: UIImage?, heatmap: UIImage?, at y: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var yPos = y
        let imageHeight: CGFloat = 160
        let halfWidth = (width - 10) / 2

        if let img = annotated {
            img.draw(in: CGRect(x: margin, y: yPos, width: halfWidth, height: imageHeight))
            let caption: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray]
            "Annotated Image".draw(at: CGPoint(x: margin, y: yPos + imageHeight + 2), withAttributes: caption)
        }

        if let img = heatmap {
            img.draw(in: CGRect(x: margin + halfWidth + 10, y: yPos, width: halfWidth, height: imageHeight))
            let caption: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray]
            "Depth Heatmap".draw(at: CGPoint(x: margin + halfWidth + 10, y: yPos + imageHeight + 2), withAttributes: caption)
        }

        yPos += imageHeight + 24
        return yPos
    }

    private static func drawMeasurementsTable(measurements: WoundMeasurement, at y: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var yPos = y

        let sectionTitle: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        "Wound Measurements".draw(at: CGPoint(x: margin, y: yPos), withAttributes: sectionTitle)
        yPos += 22

        let rows: [(String, String)] = [
            ("Surface Area", String(format: "%.2f cm²", measurements.areaCm2)),
            ("Maximum Depth", String(format: "%.2f mm", measurements.maxDepthMm)),
            ("Average Depth", String(format: "%.2f mm", measurements.avgDepthMm)),
            ("Volume", String(format: "%.2f mL", measurements.volumeMl)),
            ("Length", String(format: "%.1f mm", measurements.lengthMm)),
            ("Width", String(format: "%.1f mm", measurements.widthMm)),
            ("Perimeter", String(format: "%.1f mm", measurements.perimeterMm)),
        ]

        let rowHeight: CGFloat = 22
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.darkGray]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.black]

        for (index, row) in rows.enumerated() {
            let rowY = yPos + CGFloat(index) * rowHeight
            if index % 2 == 0 {
                UIColor.systemGray6.setFill()
                UIBezierPath(rect: CGRect(x: margin, y: rowY, width: width, height: rowHeight)).fill()
            }
            row.0.draw(at: CGPoint(x: margin + 8, y: rowY + 4), withAttributes: labelAttrs)
            row.1.draw(at: CGPoint(x: margin + width - 100, y: rowY + 4), withAttributes: valueAttrs)
        }

        yPos += CGFloat(rows.count) * rowHeight + 16
        return yPos
    }

    private static func drawPUSHScore(score: PUSHScore, at y: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var yPos = y
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        "PUSH Score: \(score.totalScore)/\(score.maxPossible) — \(score.interpretation)".draw(at: CGPoint(x: margin, y: yPos), withAttributes: attrs)
        yPos += 24
        return yPos
    }

    private static func drawClinicalSummary(text: String, at y: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var yPos = y
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.black]
        "Clinical Summary".draw(at: CGPoint(x: margin, y: yPos), withAttributes: titleAttrs)
        yPos += 22

        let textAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.darkGray]
        let textRect = CGRect(x: margin, y: yPos, width: width, height: 200)
        (text as NSString).draw(in: textRect, withAttributes: textAttrs)
        yPos += 80
        return yPos
    }

    private static func drawSnapshot(image: UIImage, at y: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var yPos = y + 16
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.black]
        "3D Reconstruction".draw(at: CGPoint(x: margin, y: yPos), withAttributes: titleAttrs)
        yPos += 22
        image.draw(in: CGRect(x: margin, y: yPos, width: width, height: 250))
        yPos += 260
        return yPos
    }

    private static func drawSignatureLine(at y: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        var yPos = y
        UIColor.black.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: yPos))
        line.addLine(to: CGPoint(x: margin + 200, y: yPos))
        line.lineWidth = 0.5
        line.stroke()

        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray]
        "Clinician Signature".draw(at: CGPoint(x: margin, y: yPos + 4), withAttributes: attrs)

        let dateLine = UIBezierPath()
        dateLine.move(to: CGPoint(x: margin + 250, y: yPos))
        dateLine.addLine(to: CGPoint(x: margin + 400, y: yPos))
        dateLine.lineWidth = 0.5
        dateLine.stroke()
        "Date".draw(at: CGPoint(x: margin + 250, y: yPos + 4), withAttributes: attrs)

        yPos += 30
        return yPos
    }

    private static func drawFooter(pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat, pageNumber: Int) {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray]
        let footer = "Generated by CarePlix WoundOS V2 — For clinical use — Page \(pageNumber)"
        let size = footer.size(withAttributes: attrs)
        footer.draw(at: CGPoint(x: (pageWidth - size.width) / 2, y: pageHeight - margin + 10), withAttributes: attrs)
    }
}
