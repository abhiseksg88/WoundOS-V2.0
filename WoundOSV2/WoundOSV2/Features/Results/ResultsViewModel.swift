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

    let serverResponse: ServerResponse

    init(response: ServerResponse, patient: Patient? = nil) {
        self.serverResponse = response
        self.measurements = response.measurements
        self.clinicalSummary = response.clinicalSummary
        self.pushScore = response.pushScore
        self.patient = patient

        // Decode images
        if let data = Data(base64Encoded: response.annotatedImageBase64) {
            self.annotatedImage = UIImage(data: data)
        }
        if let data = Data(base64Encoded: response.depthHeatmapBase64) {
            self.depthHeatmap = UIImage(data: data)
        }
        if let data = Data(base64Encoded: response.woundMaskBase64) {
            self.woundMask = UIImage(data: data)
        }
    }

    func saveToStore() {
        guard var scan = scan else { return }
        scan.measurements = measurements
        scan.pushScore = pushScore
        scan.clinicalSummary = clinicalSummary
        scan.status = .complete
        ScanStore.shared.saveScan(scan)
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
