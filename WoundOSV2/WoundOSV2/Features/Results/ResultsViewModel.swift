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
    @Published var quality: ServerResponse.ResultQuality
    @Published var isRefining: Bool

    let serverResponse: ServerResponse

    init(response: ServerResponse, patient: Patient? = nil, patientId: UUID? = nil) {
        self.serverResponse = response
        self.measurements = response.measurements
        self.clinicalSummary = response.clinicalSummary
        self.pushScore = response.pushScore
        self.patient = patient
        self.quality = response.quality
        self.isRefining = response.quality == .preliminary

        if let data = Data(base64Encoded: response.annotatedImageBase64) {
            self.annotatedImage = UIImage(data: data)
        }
        if let data = Data(base64Encoded: response.depthHeatmapBase64) {
            self.depthHeatmap = UIImage(data: data)
        }
        if let data = Data(base64Encoded: response.woundMaskBase64) {
            self.woundMask = UIImage(data: data)
        }

        // Create WoundScan and persist images
        let scanId = UUID()
        let scanDir = ScanStore.scanDirectory(for: scanId)
        let pid = patient?.id ?? patientId ?? UUID()

        var newScan = WoundScan(
            id: scanId, patientId: pid, capturedAt: Date(),
            bodyLocation: .other, woundType: .other,
            measurements: response.measurements, pushScore: response.pushScore,
            clinicalSummary: response.clinicalSummary, status: .complete
        )

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

    func updateWithGoldResults(_ gold: ServerResponse) {
        guard gold.quality == .gold else { return }

        self.quality = .gold
        self.isRefining = false
        self.measurements = gold.measurements
        self.clinicalSummary = gold.clinicalSummary
        self.pushScore = gold.pushScore

        if let data = Data(base64Encoded: gold.annotatedImageBase64) {
            self.annotatedImage = UIImage(data: data)
        }
        if let data = Data(base64Encoded: gold.depthHeatmapBase64) {
            self.depthHeatmap = UIImage(data: data)
        }
        if let data = Data(base64Encoded: gold.woundMaskBase64) {
            self.woundMask = UIImage(data: data)
        }

        // Re-persist with gold data
        if var scan = self.scan {
            scan.measurements = gold.measurements
            scan.pushScore = gold.pushScore
            scan.clinicalSummary = gold.clinicalSummary

            let scanDir = ScanStore.scanDirectory(for: scan.id)
            if let imgData = Data(base64Encoded: gold.annotatedImageBase64) {
                try? imgData.write(to: scanDir.appendingPathComponent("annotated.jpg"))
            }
            if let imgData = Data(base64Encoded: gold.depthHeatmapBase64) {
                try? imgData.write(to: scanDir.appendingPathComponent("heatmap.jpg"))
            }
            if let imgData = Data(base64Encoded: gold.woundMaskBase64) {
                try? imgData.write(to: scanDir.appendingPathComponent("mask.jpg"))
            }
            if let meshData = gold.meshOBJData {
                try? meshData.write(to: scanDir.appendingPathComponent("mesh.obj"))
                scan.meshOBJPath = "scans/\(scan.id.uuidString)/mesh.obj"
            }

            self.scan = scan
            saveToStore()
        }
    }

    func generatePDF() {
        guard let scan = scan else { return }
        let reportData = PDFReportGenerator.ReportData(
            patient: patient, scan: scan, measurements: measurements,
            pushScore: pushScore, clinicalSummary: clinicalSummary,
            annotatedImage: annotatedImage, depthHeatmap: depthHeatmap, meshSnapshot: nil
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
