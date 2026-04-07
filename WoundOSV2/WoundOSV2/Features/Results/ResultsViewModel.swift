import Foundation
import UIKit
import Combine

final class ResultsViewModel: ObservableObject {
    @Published var measurements: WoundMeasurement
    @Published var annotatedImage: UIImage?
    @Published var depthHeatmap: UIImage?
    @Published var woundMask: UIImage?
    @Published var clinicalSummary: String
    @Published var pushScore: PUSHScore?
    @Published var scan: WoundScan?
    @Published var patient: Patient?
    @Published var pdfURL: URL?

    let serverResponse: ServerResponse

    init(response: ServerResponse, patient: Patient? = nil, patientId: UUID? = nil) {
        self.serverResponse = response
        self.measurements = response.measurements
        self.clinicalSummary = response.clinicalSummary
        self.pushScore = response.pushScore
        self.patient = patient

        // Decode images from base64
        if let data = Data(base64Encoded: response.annotatedImageBase64) {
            self.annotatedImage = UIImage(data: data)
        }
        if let data = Data(base64Encoded: response.depthHeatmapBase64) {
            self.depthHeatmap = UIImage(data: data)
        }
        if let data = Data(base64Encoded: response.woundMaskBase64) {
            self.woundMask = UIImage(data: data)
        }

        // Create WoundScan from server response and persist images
        let scanId = UUID()
        let scanDir = ScanStore.scanDirectory(for: scanId)
        let pid = patient?.id ?? patientId ?? UUID()

        var newScan = WoundScan(
            id: scanId,
            patientId: pid,
            capturedAt: Date(),
            bodyLocation: .other,
            woundType: .other,
            measurements: response.measurements,
            pushScore: response.pushScore,
            clinicalSummary: response.clinicalSummary,
            status: .complete,
            healingTrend: nil
        )

        // Save images to disk
        if let imgData = Data(base64Encoded: response.annotatedImageBase64) {
            let path = scanDir.appendingPathComponent("annotated.jpg")
            try? imgData.write(to: path)
            newScan.annotatedImagePath = "scans/\(scanId.uuidString)/annotated.jpg"
        }
        if let imgData = Data(base64Encoded: response.depthHeatmapBase64) {
            let path = scanDir.appendingPathComponent("heatmap.jpg")
            try? imgData.write(to: path)
            newScan.depthHeatmapPath = "scans/\(scanId.uuidString)/heatmap.jpg"
        }
        if let imgData = Data(base64Encoded: response.woundMaskBase64) {
            let path = scanDir.appendingPathComponent("mask.jpg")
            try? imgData.write(to: path)
            newScan.woundMaskPath = "scans/\(scanId.uuidString)/mask.jpg"
        }
        if let meshData = response.meshOBJData {
            let path = scanDir.appendingPathComponent("mesh.obj")
            try? meshData.write(to: path)
            newScan.meshOBJPath = "scans/\(scanId.uuidString)/mesh.obj"
        }

        self.scan = newScan
    }

    func saveToStore() {
        guard let scan = scan else { return }
        ScanStore.shared.saveScan(scan)
    }

    func generatePDF() {
        guard let scan = scan else { return }
        let reportData = PDFReportGenerator.ReportData(
            patient: patient,
            scan: scan,
            measurements: measurements,
            pushScore: pushScore,
            clinicalSummary: clinicalSummary,
            annotatedImage: annotatedImage,
            depthHeatmap: depthHeatmap,
            meshSnapshot: nil
        )
        pdfURL = PDFReportGenerator.generateReport(data: reportData)
    }

    var areaTrend: MetricTrend? {
        guard let patient = patient else { return nil }
        let completedScans = patient.wounds.filter { $0.status == .complete && $0.measurements != nil }
        guard let previous = completedScans.sorted(by: { $0.capturedAt > $1.capturedAt }).dropFirst().first,
              let prevMeasurements = previous.measurements else { return nil }

        let delta = ((measurements.areaCm2 - prevMeasurements.areaCm2) / prevMeasurements.areaCm2) * 100
        if delta < -5 { return .improving(abs(delta)) }
        if delta > 5 { return .worsening(delta) }
        return .stable
    }
}
