import Foundation

struct Patient: Identifiable, Codable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var dateOfBirth: Date?
    var mrn: String?
    var facilityName: String?
    var roomNumber: String?
    var wounds: [WoundScan]
    var createdAt: Date

    var fullName: String { "\(firstName) \(lastName)" }
    var initials: String {
        let f = firstName.prefix(1).uppercased()
        let l = lastName.prefix(1).uppercased()
        return "\(f)\(l)"
    }

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        dateOfBirth: Date? = nil,
        mrn: String? = nil,
        facilityName: String? = nil,
        roomNumber: String? = nil,
        wounds: [WoundScan] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.mrn = mrn
        self.facilityName = facilityName
        self.roomNumber = roomNumber
        self.wounds = wounds
        self.createdAt = createdAt
    }
}
