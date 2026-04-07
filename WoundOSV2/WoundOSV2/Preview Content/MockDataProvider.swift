import Foundation

enum MockDataProvider {
    static let patients: [Patient] = {
        let cal = Calendar.current
        let now = Date()

        let p1Id = UUID()
        let p2Id = UUID()
        let p3Id = UUID()
        let p4Id = UUID()
        let p5Id = UUID()

        func date(daysAgo: Int) -> Date {
            cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }

        let scans1: [WoundScan] = [
            WoundScan(
                patientId: p1Id,
                capturedAt: date(daysAgo: 2),
                bodyLocation: .sacrum,
                woundType: .pressureInjury,
                measurements: WoundMeasurement(
                    areaCm2: 12.4, maxDepthMm: 5.2, avgDepthMm: 2.8,
                    volumeMl: 3.1, lengthMm: 45.0, widthMm: 32.0, perimeterMm: 128.5
                ),
                pushScore: PUSHScore(areaScore: 9, exudateScore: 2, surfaceTypeScore: 3),
                clinicalSummary: "Stage III pressure injury on sacrum. Granulation tissue present in wound bed with moderate serous exudate. Periwound skin intact with mild erythema. Recommend continued offloading and moisture management.",
                status: .complete,
                healingTrend: .healing
            ),
            WoundScan(
                patientId: p1Id,
                capturedAt: date(daysAgo: 9),
                bodyLocation: .sacrum,
                woundType: .pressureInjury,
                measurements: WoundMeasurement(
                    areaCm2: 14.1, maxDepthMm: 6.0, avgDepthMm: 3.4,
                    volumeMl: 4.2, lengthMm: 48.0, widthMm: 35.0, perimeterMm: 135.0
                ),
                pushScore: PUSHScore(areaScore: 9, exudateScore: 2, surfaceTypeScore: 3),
                clinicalSummary: "Stage III sacral pressure injury with mixed granulation and slough tissue. Moderate exudate noted.",
                status: .complete,
                healingTrend: .stable
            ),
        ]

        let scans2: [WoundScan] = [
            WoundScan(
                patientId: p2Id,
                capturedAt: date(daysAgo: 1),
                bodyLocation: .heel_left,
                woundType: .diabeticUlcer,
                measurements: WoundMeasurement(
                    areaCm2: 3.8, maxDepthMm: 2.1, avgDepthMm: 1.0,
                    volumeMl: 0.4, lengthMm: 22.0, widthMm: 18.0, perimeterMm: 68.0
                ),
                pushScore: PUSHScore(areaScore: 5, exudateScore: 1, surfaceTypeScore: 2),
                clinicalSummary: "Diabetic foot ulcer on left heel with healthy granulation tissue. Minimal serous drainage. Good perfusion noted.",
                status: .complete,
                healingTrend: .healing
            ),
            WoundScan(
                patientId: p2Id,
                capturedAt: date(daysAgo: 5),
                bodyLocation: .foot_left,
                woundType: .diabeticUlcer,
                measurements: WoundMeasurement(
                    areaCm2: 2.1, maxDepthMm: 1.5, avgDepthMm: 0.7,
                    volumeMl: 0.2, lengthMm: 16.0, widthMm: 14.0, perimeterMm: 52.0
                ),
                pushScore: PUSHScore(areaScore: 4, exudateScore: 1, surfaceTypeScore: 1),
                clinicalSummary: "Small diabetic ulcer on left foot dorsum. Epithelializing edges. Minimal drainage.",
                status: .complete,
                healingTrend: .healing
            ),
        ]

        let scans3: [WoundScan] = [
            WoundScan(
                patientId: p3Id,
                capturedAt: date(daysAgo: 0),
                bodyLocation: .shin_left,
                woundType: .venousUlcer,
                measurements: WoundMeasurement(
                    areaCm2: 8.6, maxDepthMm: 3.5, avgDepthMm: 1.8,
                    volumeMl: 1.5, lengthMm: 38.0, widthMm: 28.0, perimeterMm: 105.0
                ),
                pushScore: PUSHScore(areaScore: 7, exudateScore: 3, surfaceTypeScore: 3),
                clinicalSummary: "Venous leg ulcer with heavy exudate and slough tissue. Compression therapy ongoing. Periwound maceration present.",
                status: .complete,
                healingTrend: .worsening
            ),
            WoundScan(
                patientId: p3Id,
                capturedAt: date(daysAgo: 7),
                bodyLocation: .shin_left,
                woundType: .venousUlcer,
                measurements: WoundMeasurement(
                    areaCm2: 7.9, maxDepthMm: 3.2, avgDepthMm: 1.6,
                    volumeMl: 1.3, lengthMm: 36.0, widthMm: 26.0, perimeterMm: 99.0
                ),
                pushScore: PUSHScore(areaScore: 7, exudateScore: 2, surfaceTypeScore: 3),
                clinicalSummary: "Venous ulcer showing some increase in size. Increased exudate noted since last assessment.",
                status: .complete,
                healingTrend: .stable
            ),
            WoundScan(
                patientId: p3Id,
                capturedAt: date(daysAgo: 14),
                bodyLocation: .shin_left,
                woundType: .venousUlcer,
                measurements: WoundMeasurement(
                    areaCm2: 6.5, maxDepthMm: 2.8, avgDepthMm: 1.4,
                    volumeMl: 0.9, lengthMm: 32.0, widthMm: 24.0, perimeterMm: 88.0
                ),
                pushScore: PUSHScore(areaScore: 6, exudateScore: 2, surfaceTypeScore: 2),
                clinicalSummary: "Venous ulcer with mixed granulation tissue. Moderate exudate.",
                status: .complete,
                healingTrend: .stable
            ),
        ]

        let scans4: [WoundScan] = [
            WoundScan(
                patientId: p4Id,
                capturedAt: date(daysAgo: 3),
                bodyLocation: .abdomen,
                woundType: .surgicalWound,
                measurements: WoundMeasurement(
                    areaCm2: 5.2, maxDepthMm: 8.0, avgDepthMm: 4.5,
                    volumeMl: 2.3, lengthMm: 65.0, widthMm: 12.0, perimeterMm: 155.0
                ),
                pushScore: PUSHScore(areaScore: 6, exudateScore: 1, surfaceTypeScore: 2),
                clinicalSummary: "Surgical wound dehiscence, healing by secondary intention. Clean wound bed with granulation tissue. Light serous drainage.",
                status: .complete,
                healingTrend: .healing
            ),
        ]

        let scans5: [WoundScan] = [
            WoundScan(
                patientId: p5Id,
                capturedAt: date(daysAgo: 0),
                bodyLocation: .back_lower,
                woundType: .pressureInjury,
                measurements: nil,
                pushScore: nil,
                clinicalSummary: nil,
                status: .processing,
                healingTrend: nil
            ),
            WoundScan(
                patientId: p5Id,
                capturedAt: date(daysAgo: 4),
                bodyLocation: .hip_right,
                woundType: .pressureInjury,
                measurements: WoundMeasurement(
                    areaCm2: 1.8, maxDepthMm: 1.2, avgDepthMm: 0.6,
                    volumeMl: 0.1, lengthMm: 18.0, widthMm: 12.0, perimeterMm: 48.0
                ),
                pushScore: PUSHScore(areaScore: 3, exudateScore: 0, surfaceTypeScore: 1),
                clinicalSummary: "Stage II pressure injury on right hip. Epithelializing wound bed. No drainage. Good response to repositioning protocol.",
                status: .complete,
                healingTrend: .healing
            ),
        ]

        return [
            Patient(id: p1Id, firstName: "Margaret", lastName: "Chen", dateOfBirth: cal.date(from: DateComponents(year: 1942, month: 3, day: 15)), mrn: "MRN-2847501", facilityName: "Sunrise Care Center", roomNumber: "204-A", wounds: scans1, createdAt: date(daysAgo: 30)),
            Patient(id: p2Id, firstName: "James", lastName: "Rodriguez", dateOfBirth: cal.date(from: DateComponents(year: 1958, month: 8, day: 22)), mrn: "MRN-1935824", facilityName: "Sunrise Care Center", roomNumber: "118-B", wounds: scans2, createdAt: date(daysAgo: 20)),
            Patient(id: p3Id, firstName: "Dorothy", lastName: "Williams", dateOfBirth: cal.date(from: DateComponents(year: 1948, month: 11, day: 7)), mrn: "MRN-3061749", facilityName: "Valley Medical Center", roomNumber: "312", wounds: scans3, createdAt: date(daysAgo: 25)),
            Patient(id: p4Id, firstName: "Robert", lastName: "Nakamura", dateOfBirth: cal.date(from: DateComponents(year: 1965, month: 6, day: 30)), mrn: "MRN-4428163", facilityName: "Valley Medical Center", roomNumber: "205", wounds: scans4, createdAt: date(daysAgo: 10)),
            Patient(id: p5Id, firstName: "Helen", lastName: "Okafor", dateOfBirth: cal.date(from: DateComponents(year: 1939, month: 1, day: 19)), mrn: "MRN-5572390", facilityName: "Sunrise Care Center", roomNumber: "301-A", wounds: scans5, createdAt: date(daysAgo: 15)),
        ]
    }()

    static var allScans: [WoundScan] {
        patients.flatMap { $0.wounds }.sorted { $0.capturedAt > $1.capturedAt }
    }

    static func patient(forScan scan: WoundScan) -> Patient? {
        patients.first { $0.id == scan.patientId }
    }
}
