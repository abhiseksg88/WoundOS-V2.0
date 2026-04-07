import Foundation
import Metal
import MetalKit

final class SplatRenderer {
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var splatCount: Int = 0
    private var isReady: Bool = false

    init() {
        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal not available on this device")
            return
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        // Pipeline setup deferred until .splat file is loaded
    }

    func loadSplatFile(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }

        // Parse .splat binary format
        // Each Gaussian: position(3f) + scale(3f) + rotation(4f) + SH(48f) + opacity(1f) = ~232 bytes
        let gaussianSize = 232
        splatCount = data.count / gaussianSize

        if splatCount > 0 {
            isReady = true
            return true
        }
        return false
    }

    var gaussianCount: Int { splatCount }
    var available: Bool { isReady && device != nil }

    func render(in view: MTKView) {
        // Full implementation in Phase 5
        // For now, this is a stub
    }
}
