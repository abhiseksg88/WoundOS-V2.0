import Foundation
import CoreData
import Combine

final class ScanStore: ObservableObject {
    static let shared = ScanStore()

    let container: NSPersistentContainer
    @Published var patients: [Patient] = []
    @Published var recentScans: [WoundScan] = []

    private init() {
        container = NSPersistentContainer(name: "WoundOSV2")
        container.loadPersistentStores { _, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var context: NSManagedObjectContext { container.viewContext }

    // MARK: - Patient CRUD

    func savePatient(_ patient: Patient) {
        let entity = PatientEntity(context: context)
        entity.id = patient.id
        entity.firstName = patient.firstName
        entity.lastName = patient.lastName
        entity.dateOfBirth = patient.dateOfBirth
        entity.mrn = patient.mrn
        entity.facilityName = patient.facilityName
        entity.roomNumber = patient.roomNumber
        entity.createdAt = patient.createdAt
        save()
    }

    func fetchPatients() -> [Patient] {
        let request: NSFetchRequest<PatientEntity> = PatientEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PatientEntity.createdAt, ascending: false)]
        do {
            let entities = try context.fetch(request)
            return entities.map { mapPatient($0) }
        } catch {
            print("Failed to fetch patients: \(error)")
            return []
        }
    }

    func deletePatient(id: UUID) {
        let request: NSFetchRequest<PatientEntity> = PatientEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        do {
            let results = try context.fetch(request)
            results.forEach { context.delete($0) }
            save()
        } catch {
            print("Failed to delete patient: \(error)")
        }
    }

    // MARK: - Scan CRUD

    func saveScan(_ scan: WoundScan) {
        let entity = ScanEntity(context: context)
        entity.id = scan.id
        entity.patientId = scan.patientId
        entity.capturedAt = scan.capturedAt
        entity.status = scan.status.rawValue
        entity.bodyLocation = scan.bodyLocation.rawValue
        entity.woundType = scan.woundType.rawValue
        entity.healingTrend = scan.healingTrend?.rawValue
        entity.clinicalSummary = scan.clinicalSummary
        entity.annotatedImagePath = scan.annotatedImagePath
        entity.depthHeatmapPath = scan.depthHeatmapPath
        entity.woundMaskPath = scan.woundMaskPath
        entity.meshOBJPath = scan.meshOBJPath
        entity.splatFilePath = scan.splatFilePath
        entity.pdfReportPath = scan.pdfReportPath

        if let measurements = scan.measurements,
           let data = try? JSONEncoder().encode(measurements) {
            entity.measurementsJSON = String(data: data, encoding: .utf8)
        }
        if let pushScore = scan.pushScore,
           let data = try? JSONEncoder().encode(pushScore) {
            entity.pushScoreJSON = String(data: data, encoding: .utf8)
        }
        save()
    }

    func fetchScans(forPatient patientId: UUID) -> [WoundScan] {
        let request: NSFetchRequest<ScanEntity> = ScanEntity.fetchRequest()
        request.predicate = NSPredicate(format: "patientId == %@", patientId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScanEntity.capturedAt, ascending: false)]
        do {
            let entities = try context.fetch(request)
            return entities.map { mapScan($0) }
        } catch {
            print("Failed to fetch scans: \(error)")
            return []
        }
    }

    func fetchRecentScans(limit: Int = 10) -> [WoundScan] {
        let request: NSFetchRequest<ScanEntity> = ScanEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScanEntity.capturedAt, ascending: false)]
        request.fetchLimit = limit
        do {
            let entities = try context.fetch(request)
            return entities.map { mapScan($0) }
        } catch {
            print("Failed to fetch recent scans: \(error)")
            return []
        }
    }

    func deleteScan(id: UUID) {
        let request: NSFetchRequest<ScanEntity> = ScanEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        do {
            let results = try context.fetch(request)
            results.forEach { context.delete($0) }
            save()
        } catch {
            print("Failed to delete scan: \(error)")
        }
    }

    // MARK: - File Management

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func scanDirectory(for scanId: UUID) -> URL {
        let dir = documentsDirectory.appendingPathComponent("scans/\(scanId.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Private

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Core Data save error: \(error)")
        }
    }

    private func mapPatient(_ entity: PatientEntity) -> Patient {
        let scans = (entity.scans as? Set<ScanEntity>)?.map { mapScan($0) } ?? []
        return Patient(
            id: entity.id ?? UUID(),
            firstName: entity.firstName ?? "",
            lastName: entity.lastName ?? "",
            dateOfBirth: entity.dateOfBirth,
            mrn: entity.mrn,
            facilityName: entity.facilityName,
            roomNumber: entity.roomNumber,
            wounds: scans.sorted { $0.capturedAt > $1.capturedAt },
            createdAt: entity.createdAt ?? Date()
        )
    }

    private func mapScan(_ entity: ScanEntity) -> WoundScan {
        var measurements: WoundMeasurement?
        if let json = entity.measurementsJSON,
           let data = json.data(using: .utf8) {
            measurements = try? JSONDecoder().decode(WoundMeasurement.self, from: data)
        }

        var pushScore: PUSHScore?
        if let json = entity.pushScoreJSON,
           let data = json.data(using: .utf8) {
            pushScore = try? JSONDecoder().decode(PUSHScore.self, from: data)
        }

        var scan = WoundScan(
            id: entity.id ?? UUID(),
            patientId: entity.patientId ?? UUID(),
            capturedAt: entity.capturedAt ?? Date(),
            bodyLocation: WoundBodyLocation(rawValue: entity.bodyLocation ?? "") ?? .other,
            woundType: WoundType(rawValue: entity.woundType ?? "") ?? .other,
            measurements: measurements,
            pushScore: pushScore,
            clinicalSummary: entity.clinicalSummary,
            status: WoundScan.ScanStatus(rawValue: entity.status ?? "") ?? .failed,
            healingTrend: HealingTrend(rawValue: entity.healingTrend ?? "")
        )
        scan.annotatedImagePath = entity.annotatedImagePath
        scan.depthHeatmapPath = entity.depthHeatmapPath
        scan.woundMaskPath = entity.woundMaskPath
        scan.meshOBJPath = entity.meshOBJPath
        scan.splatFilePath = entity.splatFilePath
        scan.pdfReportPath = entity.pdfReportPath
        return scan
    }
}
