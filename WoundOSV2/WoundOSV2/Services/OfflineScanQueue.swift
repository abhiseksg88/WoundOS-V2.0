import Foundation
import Network
import Combine

final class OfflineScanQueue: ObservableObject {
    static let shared = OfflineScanQueue()

    @Published var queuedScans: [QueuedScan] = []
    @Published var isOnline: Bool = true
    @Published var isUploading: Bool = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.careplix.woundos.networkmonitor")

    struct QueuedScan: Identifiable, Codable {
        let id: UUID
        let patientId: UUID
        let capturedAt: Date
        let framesDirectory: String
        var status: QueueStatus

        enum QueueStatus: String, Codable {
            case queued, uploading, failed
        }
    }

    private init() {
        startMonitoring()
        loadQueue()
    }

    var pendingCount: Int {
        queuedScans.filter { $0.status == .queued || $0.status == .failed }.count
    }

    func enqueue(scanId: UUID, patientId: UUID, framesDirectory: String) {
        let queued = QueuedScan(
            id: scanId,
            patientId: patientId,
            capturedAt: Date(),
            framesDirectory: framesDirectory,
            status: .queued
        )
        queuedScans.append(queued)
        saveQueue()

        if isOnline {
            processQueue()
        }
    }

    func processQueue() {
        guard isOnline, !isUploading else { return }
        guard let next = queuedScans.first(where: { $0.status == .queued || $0.status == .failed }) else { return }

        isUploading = true
        updateStatus(for: next.id, status: .uploading)

        Task {
            do {
                // Load frames from disk
                let framesDir = URL(fileURLWithPath: next.framesDirectory)
                let fileManager = FileManager.default
                let frameFiles = try fileManager.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "jpg" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }

                var frames: [SelectedFrame] = []
                for (index, fileURL) in frameFiles.enumerated() {
                    let data = try Data(contentsOf: fileURL)
                    let frame = SelectedFrame(
                        index: index,
                        jpegData: data,
                        pose: CameraPose.identity,
                        intrinsics: CameraIntrinsics.defaultiPhone,
                        timestamp: TimeInterval(index)
                    )
                    frames.append(frame)
                }

                // Load poses if saved alongside frames
                let posesURL = framesDir.appendingPathComponent("poses.json")
                if let posesData = try? Data(contentsOf: posesURL),
                   let poses = try? JSONDecoder().decode([CameraPose].self, from: posesData) {
                    for i in 0..<min(frames.count, poses.count) {
                        frames[i] = SelectedFrame(
                            index: i,
                            jpegData: frames[i].jpegData,
                            pose: poses[i],
                            intrinsics: frames[i].intrinsics,
                            timestamp: poses[i].timestamp
                        )
                    }
                }

                // Upload via ReconstructionService
                let service = ReconstructionService()
                let _ = try await service.uploadScan(
                    frames: frames,
                    woundPoint: nil,
                    useWoundAmbit: true,
                    generateSplat: false
                )

                await MainActor.run {
                    self.queuedScans.removeAll { $0.id == next.id }
                    self.saveQueue()
                    self.isUploading = false
                    self.processQueue() // Process next
                }
            } catch {
                await MainActor.run {
                    self.updateStatus(for: next.id, status: .failed)
                    self.isUploading = false
                }
            }
        }
    }

    func removeFromQueue(scanId: UUID) {
        queuedScans.removeAll { $0.id == scanId }
        saveQueue()
    }

    // MARK: - Network Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOffline = !(self?.isOnline ?? true)
                self?.isOnline = path.status == .satisfied

                if wasOffline && path.status == .satisfied {
                    self?.processQueue()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Persistence

    private var queueFileURL: URL {
        ScanStore.documentsDirectory.appendingPathComponent("offline_queue.json")
    }

    private func saveQueue() {
        if let data = try? JSONEncoder().encode(queuedScans) {
            try? data.write(to: queueFileURL)
        }
    }

    private func loadQueue() {
        guard let data = try? Data(contentsOf: queueFileURL) else { return }
        queuedScans = (try? JSONDecoder().decode([QueuedScan].self, from: data)) ?? []
    }

    private func updateStatus(for id: UUID, status: QueuedScan.QueueStatus) {
        if let index = queuedScans.firstIndex(where: { $0.id == id }) {
            queuedScans[index].status = status
            saveQueue()
        }
    }
}
