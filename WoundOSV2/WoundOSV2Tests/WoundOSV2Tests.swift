import XCTest
@testable import WoundOSV2

final class WoundOSV2Tests: XCTestCase {
    func testPatientFullName() {
        let patient = Patient(firstName: "John", lastName: "Doe")
        XCTAssertEqual(patient.fullName, "John Doe")
    }

    func testPatientInitials() {
        let patient = Patient(firstName: "Margaret", lastName: "Chen")
        XCTAssertEqual(patient.initials, "MC")
    }

    func testWoundMeasurementCodable() throws {
        let measurement = WoundMeasurement(
            areaCm2: 12.4, maxDepthMm: 5.2, avgDepthMm: 2.8,
            volumeMl: 3.1, lengthMm: 45.0, widthMm: 32.0, perimeterMm: 128.5
        )
        let data = try JSONEncoder().encode(measurement)
        let decoded = try JSONDecoder().decode(WoundMeasurement.self, from: data)
        XCTAssertEqual(decoded.areaCm2, 12.4)
        XCTAssertEqual(decoded.maxDepthMm, 5.2)
    }

    func testPUSHScoreCalculation() {
        let score = PUSHScore(areaScore: 9, exudateScore: 2, surfaceTypeScore: 3)
        XCTAssertEqual(score.totalScore, 14)
        XCTAssertEqual(score.interpretation, "Significant concern")
    }

    func testPUSHScoreHealed() {
        let score = PUSHScore(areaScore: 0, exudateScore: 0, surfaceTypeScore: 0)
        XCTAssertEqual(score.totalScore, 0)
        XCTAssertEqual(score.interpretation, "Healed")
    }

    func testPUSHAreaScoreMapping() {
        XCTAssertEqual(PUSHScore.areaScore(forAreaCm2: 0), 0)
        XCTAssertEqual(PUSHScore.areaScore(forAreaCm2: 0.5), 2)
        XCTAssertEqual(PUSHScore.areaScore(forAreaCm2: 5.0), 7)
        XCTAssertEqual(PUSHScore.areaScore(forAreaCm2: 25.0), 10)
    }

    func testWoundScanCodable() throws {
        let scan = WoundScan(
            patientId: UUID(),
            bodyLocation: .sacrum,
            woundType: .pressureInjury,
            status: .complete,
            healingTrend: .healing
        )
        let data = try JSONEncoder().encode(scan)
        let decoded = try JSONDecoder().decode(WoundScan.self, from: data)
        XCTAssertEqual(decoded.bodyLocation, .sacrum)
        XCTAssertEqual(decoded.status, .complete)
    }

    func testMockDataProvider() {
        XCTAssertEqual(MockDataProvider.patients.count, 5)
        XCTAssertFalse(MockDataProvider.allScans.isEmpty)
    }

    func testBodyLocationDisplayName() {
        XCTAssertEqual(WoundBodyLocation.heel_left.displayName, "Heel Left")
        XCTAssertEqual(WoundBodyLocation.sacrum.displayName, "Sacrum")
    }

    func testCameraIntrinsicsDefault() {
        let intrinsics = CameraIntrinsics.defaultiPhone
        XCTAssertEqual(intrinsics.width, 4032)
        XCTAssertEqual(intrinsics.height, 3024)
    }
}
