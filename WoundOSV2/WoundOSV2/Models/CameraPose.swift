import Foundation

struct CameraPose: Codable, Hashable {
    let timestamp: TimeInterval
    let transform: [[Float]]

    let trackingState: TrackingState

    enum TrackingState: String, Codable, Hashable {
        case normal, limited, notAvailable
    }

    init(timestamp: TimeInterval, transform: [[Float]], trackingState: TrackingState = .normal) {
        self.timestamp = timestamp
        self.transform = transform
        self.trackingState = trackingState
    }

    static var identity: CameraPose {
        CameraPose(
            timestamp: 0,
            transform: [
                [1, 0, 0, 0],
                [0, 1, 0, 0],
                [0, 0, 1, 0],
                [0, 0, 0, 1]
            ]
        )
    }
}
