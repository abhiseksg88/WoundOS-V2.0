import Foundation

struct WoundScan: Identifiable, Codable, Hashable {
    let id: UUID
    let patientId: UUID
    var capturedAt: Date
    var bodyLocation: WoundBodyLocation
    var woundType: WoundType
    var measurements: WoundMeasurement?
    var pushScore: PUSHScore?
    var clinicalSummary: String?
    var status: ScanStatus
    var healingTrend: HealingTrend?

    var annotatedImagePath: String?
    var depthHeatmapPath: String?
    var woundMaskPath: String?
    var meshOBJPath: String?
    var splatFilePath: String?
    var pdfReportPath: String?

    enum ScanStatus: String, Codable, Hashable {
        case capturing, uploading, processing, segmenting, measuring, complete, failed
    }

    init(
        id: UUID = UUID(),
        patientId: UUID,
        capturedAt: Date = Date(),
        bodyLocation: WoundBodyLocation = .other,
        woundType: WoundType = .other,
        measurements: WoundMeasurement? = nil,
        pushScore: PUSHScore? = nil,
        clinicalSummary: String? = nil,
        status: ScanStatus = .capturing,
        healingTrend: HealingTrend? = nil
    ) {
        self.id = id
        self.patientId = patientId
        self.capturedAt = capturedAt
        self.bodyLocation = bodyLocation
        self.woundType = woundType
        self.measurements = measurements
        self.pushScore = pushScore
        self.clinicalSummary = clinicalSummary
        self.status = status
        self.healingTrend = healingTrend
    }
}

enum WoundBodyLocation: String, Codable, CaseIterable, Hashable {
    case sacrum, heel_left, heel_right, ankle_left, ankle_right
    case shin_left, shin_right, knee_left, knee_right
    case thigh_left, thigh_right, hip_left, hip_right
    case abdomen, chest, back_upper, back_lower
    case shoulder_left, shoulder_right, elbow_left, elbow_right
    case forearm_left, forearm_right, hand_left, hand_right
    case foot_left, foot_right, other

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

enum WoundType: String, Codable, CaseIterable, Hashable {
    case pressureInjury, diabeticUlcer, venousUlcer, arterialUlcer
    case surgicalWound, traumaticWound, burn, skinTear, other

    var displayName: String {
        switch self {
        case .pressureInjury: return "Pressure Injury"
        case .diabeticUlcer: return "Diabetic Ulcer"
        case .venousUlcer: return "Venous Ulcer"
        case .arterialUlcer: return "Arterial Ulcer"
        case .surgicalWound: return "Surgical Wound"
        case .traumaticWound: return "Traumatic Wound"
        case .burn: return "Burn"
        case .skinTear: return "Skin Tear"
        case .other: return "Other"
        }
    }
}

enum HealingTrend: String, Codable, Hashable {
    case healing, stable, worsening
}
