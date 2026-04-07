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
    private var cancellables = Set<AnyCancellable>()

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
                // In production, load frames from disk and upload
                try await Task.sleep(nanoseconds: 2_000_000_000)

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
