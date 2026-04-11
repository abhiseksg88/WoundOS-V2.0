import Foundation
import simd

/// Result of the on-device measurement pipeline.
///
/// Mirrors the `primary_measurement` block in the WoundOS Pro v1 data model:
/// ```
/// "primary_measurement": {
///   "source": "nurse_drawn",
///   "boundary_2d": [[142,87], ...],
///   "boundary_3d": [[0.15,0.04,0.20], ...],
///   "area_cm2": 12.4,
///   ...
///   "computed_on_device": true,
///   "processing_time_ms": 180
/// }
/// ```
struct PrimaryMeasurement: Codable, Hashable {
    /// "nurse_drawn" — primary clinical path is always nurse-drawn in v1.
    let source: Source

    /// Nurse-drawn polygon vertices in **image pixel** coordinates.
    let boundary2DPixels: [CGPoint]

    /// Same polygon ray-cast onto the LiDAR mesh — in ARKit world space (meters).
    let boundary3DMeters: [SIMD3<Float>]

    /// Computed measurements.
    let areaCm2: Double
    let maxDepthMm: Double
    let avgDepthMm: Double
    let volumeMl: Double
    let lengthMm: Double
    let widthMm: Double
    let perimeterMm: Double
    let circumferenceCm: Double

    /// Optional PUSH score, computed on-device from area + tissue percentages
    /// (tissue percentages come from a future on-device classifier; default to nil for now).
    let pushScore: PUSHScore?

    /// Marker positions for the rendered annotated image (image pixel coords).
    /// Index 0 = length endpoint A, 1 = length endpoint B,
    /// Index 2 = width endpoint A, 3 = width endpoint B.
    let markerEndpointsPixels: [CGPoint]

    /// True for the on-device path. Server-side measurements would set this false.
    let computedOnDevice: Bool

    /// Time taken by the measurement engine (ms).
    let processingTimeMs: Int

    enum Source: String, Codable, Hashable {
        case nurseDrawn = "nurse_drawn"
        case sam2 = "sam2"
        case manualAdjusted = "manual_adjusted"
    }

    // SIMD3<Float> isn't Codable by default — we use a manual encoder for the array.
    enum CodingKeys: String, CodingKey {
        case source, boundary2DPixels, boundary3DMeters
        case areaCm2, maxDepthMm, avgDepthMm, volumeMl
        case lengthMm, widthMm, perimeterMm, circumferenceCm
        case pushScore, markerEndpointsPixels, computedOnDevice, processingTimeMs
    }

    init(
        source: Source,
        boundary2DPixels: [CGPoint],
        boundary3DMeters: [SIMD3<Float>],
        areaCm2: Double,
        maxDepthMm: Double,
        avgDepthMm: Double,
        volumeMl: Double,
        lengthMm: Double,
        widthMm: Double,
        perimeterMm: Double,
        circumferenceCm: Double? = nil,
        pushScore: PUSHScore? = nil,
        markerEndpointsPixels: [CGPoint] = [],
        computedOnDevice: Bool = true,
        processingTimeMs: Int = 0
    ) {
        self.source = source
        self.boundary2DPixels = boundary2DPixels
        self.boundary3DMeters = boundary3DMeters
        self.areaCm2 = areaCm2
        self.maxDepthMm = maxDepthMm
        self.avgDepthMm = avgDepthMm
        self.volumeMl = volumeMl
        self.lengthMm = lengthMm
        self.widthMm = widthMm
        self.perimeterMm = perimeterMm
        self.circumferenceCm = circumferenceCm ?? (perimeterMm / 10.0)
        self.pushScore = pushScore
        self.markerEndpointsPixels = markerEndpointsPixels
        self.computedOnDevice = computedOnDevice
        self.processingTimeMs = processingTimeMs
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source, forKey: .source)
        try c.encode(boundary2DPixels.map { [$0.x, $0.y] }, forKey: .boundary2DPixels)
        try c.encode(boundary3DMeters.map { [$0.x, $0.y, $0.z] }, forKey: .boundary3DMeters)
        try c.encode(areaCm2, forKey: .areaCm2)
        try c.encode(maxDepthMm, forKey: .maxDepthMm)
        try c.encode(avgDepthMm, forKey: .avgDepthMm)
        try c.encode(volumeMl, forKey: .volumeMl)
        try c.encode(lengthMm, forKey: .lengthMm)
        try c.encode(widthMm, forKey: .widthMm)
        try c.encode(perimeterMm, forKey: .perimeterMm)
        try c.encode(circumferenceCm, forKey: .circumferenceCm)
        try c.encodeIfPresent(pushScore, forKey: .pushScore)
        try c.encode(markerEndpointsPixels.map { [$0.x, $0.y] }, forKey: .markerEndpointsPixels)
        try c.encode(computedOnDevice, forKey: .computedOnDevice)
        try c.encode(processingTimeMs, forKey: .processingTimeMs)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(Source.self, forKey: .source)

        let b2d = try c.decode([[CGFloat]].self, forKey: .boundary2DPixels)
        boundary2DPixels = b2d.map { CGPoint(x: $0[0], y: $0[1]) }

        let b3d = try c.decode([[Float]].self, forKey: .boundary3DMeters)
        boundary3DMeters = b3d.map { SIMD3<Float>($0[0], $0[1], $0[2]) }

        areaCm2 = try c.decode(Double.self, forKey: .areaCm2)
        maxDepthMm = try c.decode(Double.self, forKey: .maxDepthMm)
        avgDepthMm = try c.decode(Double.self, forKey: .avgDepthMm)
        volumeMl = try c.decode(Double.self, forKey: .volumeMl)
        lengthMm = try c.decode(Double.self, forKey: .lengthMm)
        widthMm = try c.decode(Double.self, forKey: .widthMm)
        perimeterMm = try c.decode(Double.self, forKey: .perimeterMm)
        circumferenceCm = try c.decode(Double.self, forKey: .circumferenceCm)
        pushScore = try c.decodeIfPresent(PUSHScore.self, forKey: .pushScore)

        let markers = try c.decodeIfPresent([[CGFloat]].self, forKey: .markerEndpointsPixels) ?? []
        markerEndpointsPixels = markers.map { CGPoint(x: $0[0], y: $0[1]) }

        computedOnDevice = try c.decode(Bool.self, forKey: .computedOnDevice)
        processingTimeMs = try c.decode(Int.self, forKey: .processingTimeMs)
    }

    /// Convert to the legacy WoundMeasurement type for compatibility with existing
    /// ResultsView, ScanStore persistence, and PDF report generator.
    var asWoundMeasurement: WoundMeasurement {
        WoundMeasurement(
            areaCm2: areaCm2,
            maxDepthMm: maxDepthMm,
            avgDepthMm: avgDepthMm,
            volumeMl: volumeMl,
            lengthMm: lengthMm,
            widthMm: widthMm,
            perimeterMm: perimeterMm,
            circumferenceCm: circumferenceCm
        )
    }
}
