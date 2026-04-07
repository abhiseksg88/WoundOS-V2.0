import Foundation

struct PUSHScore: Codable, Hashable {
    var areaScore: Int
    var exudateScore: Int
    var surfaceTypeScore: Int

    var totalScore: Int { areaScore + exudateScore + surfaceTypeScore }

    var interpretation: String {
        switch totalScore {
        case 0: return "Healed"
        case 1...5: return "Healing well"
        case 6...10: return "Moderate concern"
        case 11...14: return "Significant concern"
        default: return "Critical — immediate intervention needed"
        }
    }

    var maxPossible: Int { 17 }

    var normalizedScore: Double {
        Double(totalScore) / Double(maxPossible)
    }

    init(areaScore: Int = 0, exudateScore: Int = 0, surfaceTypeScore: Int = 0) {
        self.areaScore = min(max(areaScore, 0), 10)
        self.exudateScore = min(max(exudateScore, 0), 3)
        self.surfaceTypeScore = min(max(surfaceTypeScore, 0), 4)
    }

    static func areaScore(forAreaCm2 area: Double) -> Int {
        switch area {
        case 0: return 0
        case 0..<0.3: return 1
        case 0.3..<0.7: return 2
        case 0.7..<1.0: return 3
        case 1.0..<2.0: return 4
        case 2.0..<3.0: return 5
        case 3.0..<4.0: return 6
        case 4.0..<8.0: return 7
        case 8.0..<12.0: return 8
        case 12.0..<24.0: return 9
        default: return 10
        }
    }
}
