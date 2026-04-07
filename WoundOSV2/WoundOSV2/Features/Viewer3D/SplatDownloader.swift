import Foundation
import Combine

final class SplatDownloader: ObservableObject {
    @Published var progress: Double = 0
    @Published var isDownloading: Bool = false
    @Published var isComplete: Bool = false
    @Published var error: Error?
    @Published var localURL: URL?

    private var downloadTask: URLSessionDownloadTask?

    func download(from urlString: String, scanId: UUID) {
        guard let url = URL(string: urlString) else {
            error = URLError(.badURL)
            return
        }

        isDownloading = true
        progress = 0

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)

        let task = session.downloadTask(with: url) { [weak self] tempURL, response, downloadError in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isDownloading = false

                if let downloadError = downloadError {
                    self.error = downloadError
                    return
                }

                guard let tempURL = tempURL else {
                    self.error = URLError(.cannotOpenFile)
                    return
                }

                // Move to permanent location
                let scanDir = ScanStore.scanDirectory(for: scanId)
                let destURL = scanDir.appendingPathComponent("wound.splat")

                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    self.localURL = destURL
                    self.isComplete = true
                } catch {
                    self.error = error
                }
            }
        }

        // Observe progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.progress = progress.fractionCompleted
            }
        }
        _ = observation // Keep alive

        task.resume()
        downloadTask = task
    }

    func cancel() {
        downloadTask?.cancel()
        isDownloading = false
    }
}
