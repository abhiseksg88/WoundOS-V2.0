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

    init(
        areaCm2: Double = 0,
        maxDepthMm: Double = 0,
        avgDepthMm: Double = 0,
        volumeMl: Double = 0,
        lengthMm: Double = 0,
        widthMm: Double = 0,
        perimeterMm: Double = 0,
        underminingMm: Double? = nil,
        tunnelingMm: Double? = nil
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
    }
}
