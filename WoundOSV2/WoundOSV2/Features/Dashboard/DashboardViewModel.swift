import Foundation
import Combine

final class DashboardViewModel: ObservableObject {
    @Published var recentScans: [WoundScan] = []
    @Published var patients: [Patient] = []
    @Published var isLoading: Bool = false
    @Published var greeting: String = ""

    init() {
        updateGreeting()
        loadMockData()
    }

    func loadMockData() {
        isLoading = true
        patients = MockDataProvider.patients
        recentScans = MockDataProvider.allScans
        isLoading = false
    }

    func patientForScan(_ scan: WoundScan) -> Patient? {
        MockDataProvider.patient(forScan: scan)
    }

    private func updateGreeting() {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: greeting = "Good morning"
        case 12..<17: greeting = "Good afternoon"
        default: greeting = "Good evening"
        }
    }
}
