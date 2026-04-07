import Foundation

struct CameraIntrinsics: Codable, Hashable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    let width: Int
    let height: Int

    init(fx: Float, fy: Float, cx: Float, cy: Float, width: Int, height: Int) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.width = width
        self.height = height
    }

    static var defaultiPhone: CameraIntrinsics {
        CameraIntrinsics(
            fx: 3088.57,
            fy: 3088.57,
            cx: 2016.0,
            cy: 1512.0,
            width: 4032,
            height: 3024
        )
    }
}
