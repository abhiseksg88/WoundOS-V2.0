import Foundation

struct WoundMeasurement: Codable, Hashable {
    var areaCm2: Double
    var maxDepthMm: Double
    var avgDepthMm: Double
    var volumeMl: Double
    var lengthMm: Double
    var widthMm: Double
    var perimeterMm: Double
    var underminingMm: Double?
    var tunnelingMm: Double?

    /// Wound circumference in centimeters. If the server doesn't send this
    /// field (older backend versions), it's derived from `perimeterMm / 10`.
    var circumferenceCm: Double

    /// Length in centimeters (derived from lengthMm). Useful for the
    /// clinical-style display table that shows everything in cm.
    var lengthCm: Double { lengthMm / 10.0 }

    /// Width in centimeters (derived from widthMm).
    var widthCm: Double { widthMm / 10.0 }

    init(
        areaCm2: Double = 0,
        maxDepthMm: Double = 0,
        avgDepthMm: Double = 0,
        volumeMl: Double = 0,
        lengthMm: Double = 0,
        widthMm: Double = 0,
        perimeterMm: Double = 0,
        underminingMm: Double? = nil,
        tunnelingMm: Double? = nil,
        circumferenceCm: Double? = nil
    ) {
        self.areaCm2 = areaCm2
        self.maxDepthMm = maxDepthMm
        self.avgDepthMm = avgDepthMm
        self.volumeMl = volumeMl
        self.lengthMm = lengthMm
        self.widthMm = widthMm
        self.perimeterMm = perimeterMm
        self.underminingMm = underminingMm
        self.tunnelingMm = tunnelingMm
        // Default to perimeterMm / 10 if not explicitly provided
        self.circumferenceCm = circumferenceCm ?? (perimeterMm / 10.0)
    }

    // Backward-compatible decoding — older payloads omit `circumferenceCm`
    enum CodingKeys: String, CodingKey {
        case areaCm2, maxDepthMm, avgDepthMm, volumeMl
        case lengthMm, widthMm, perimeterMm
        case underminingMm, tunnelingMm
        case circumferenceCm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        areaCm2 = try c.decodeIfPresent(Double.self, forKey: .areaCm2) ?? 0
        maxDepthMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthMm) ?? 0
        avgDepthMm = try c.decodeIfPresent(Double.self, forKey: .avgDepthMm) ?? 0
        volumeMl = try c.decodeIfPresent(Double.self, forKey: .volumeMl) ?? 0
        lengthMm = try c.decodeIfPresent(Double.self, forKey: .lengthMm) ?? 0
        widthMm = try c.decodeIfPresent(Double.self, forKey: .widthMm) ?? 0
        perimeterMm = try c.decodeIfPresent(Double.self, forKey: .perimeterMm) ?? 0
        underminingMm = try c.decodeIfPresent(Double.self, forKey: .underminingMm)
        tunnelingMm = try c.decodeIfPresent(Double.self, forKey: .tunnelingMm)
        // Fall back to perimeterMm / 10 when the server doesn't provide it
        if let cc = try c.decodeIfPresent(Double.self, forKey: .circumferenceCm) {
            circumferenceCm = cc
        } else {
            circumferenceCm = perimeterMm / 10.0
        }
    }
}
