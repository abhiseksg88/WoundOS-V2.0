import Foundation
import Combine

final class PatientViewModel: ObservableObject {
    @Published var patients: [Patient] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false

    var filteredPatients: [Patient] {
        if searchText.isEmpty {
            return patients
        }
        let query = searchText.lowercased()
        return patients.filter {
            $0.fullName.lowercased().contains(query) ||
            ($0.mrn?.lowercased().contains(query) ?? false) ||
            ($0.roomNumber?.lowercased().contains(query) ?? false)
        }
    }

    init() {
        loadMockData()
    }

    func loadMockData() {
        isLoading = true
        patients = MockDataProvider.patients
        isLoading = false
    }

    func latestScan(for patient: Patient) -> WoundScan? {
        patient.wounds.sorted { $0.capturedAt > $1.capturedAt }.first
    }

    func woundCount(for patient: Patient) -> Int {
        patient.wounds.count
    }
}
