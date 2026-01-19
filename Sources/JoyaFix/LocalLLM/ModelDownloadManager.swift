import Foundation
import Combine

/// Manages downloading and storing local LLM models
@MainActor
class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    // MARK: - Published Properties

    @Published var downloadProgress: Double = 0
    @Published var isDownloading: Bool = false
    @Published var currentDownloadModel: LocalModelInfo?
    @Published var downloadedModels: [DownloadedModel] = []
    @Published var downloadError: Error?

    // MARK: - Private Properties

    private var downloadTask: URLSessionDownloadTask?
    private var resumeData: Data?
    private var urlSession: URLSession!
    private var progressObservation: NSKeyValueObservation?

    // MARK: - Initialization

    private override init() {
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600  // 1 hour for large downloads
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        loadDownloadedModels()
    }

    // MARK: - Public Methods

    /// Downloads a model to local storage
    func downloadModel(_ model: LocalModelInfo) async throws {
        guard !isDownloading else {
            throw ModelDownloadError.downloadInProgress
        }

        // Check available disk space
        let modelsDirectory = try getModelsDirectory()
        let availableSpace = try FileManager.default.availableCapacity(forPath: modelsDirectory.path)

        guard availableSpace > Int64(model.fileSize) + 500_000_000 else {  // 500MB buffer
            throw ModelDownloadError.insufficientDiskSpace(required: model.fileSize, available: UInt64(availableSpace))
        }

        isDownloading = true
        currentDownloadModel = model
        downloadProgress = 0
        downloadError = nil

        // Resume download if possible
        if let resumeData = resumeData {
            downloadTask = urlSession.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
        } else {
            downloadTask = urlSession.downloadTask(with: model.downloadURL)
        }

        // Observe progress
        progressObservation = downloadTask?.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.downloadProgress = progress.fractionCompleted
            }
        }

        downloadTask?.resume()
    }

    /// Cancels the current download
    func cancelDownload() {
        downloadTask?.cancel { [weak self] resumeData in
            Task { @MainActor in
                self?.resumeData = resumeData
            }
        }
        isDownloading = false
        currentDownloadModel = nil
        downloadProgress = 0
    }

    /// Deletes a downloaded model
    func deleteModel(_ model: DownloadedModel) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: model.localPath) {
            try fileManager.removeItem(atPath: model.localPath)
        }

        downloadedModels.removeAll { $0.id == model.id }
        saveDownloadedModels()

        // Clear selection if deleted model was selected
        if SettingsManager.shared.selectedLocalModel == model.id {
            SettingsManager.shared.selectedLocalModel = nil
        }

        Logger.info("Deleted local model: \(model.info.displayName)")
    }

    /// Gets the path to the models directory, creating it if needed
    func getModelsDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent(JoyaFixConstants.FilePaths.localModelsDirectory)

        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }

        return modelsDir
    }

    /// Checks available system RAM
    func availableRAM() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(vm_kernel_page_size)
        return UInt64(stats.free_count + stats.inactive_count) * pageSize
    }

    /// Gets a downloaded model by ID
    func getDownloadedModel(byId id: String) -> DownloadedModel? {
        downloadedModels.first { $0.id == id }
    }

    // MARK: - Private Methods

    private func loadDownloadedModels() {
        guard let data = UserDefaults.standard.data(forKey: JoyaFixConstants.UserDefaultsKeys.downloadedLocalModels),
              let models = try? JSONDecoder().decode([DownloadedModel].self, from: data) else {
            downloadedModels = []
            return
        }

        // Filter out models that no longer exist on disk
        downloadedModels = models.filter { $0.exists }
        saveDownloadedModels()
    }

    private func saveDownloadedModels() {
        if let data = try? JSONEncoder().encode(downloadedModels) {
            UserDefaults.standard.set(data, forKey: JoyaFixConstants.UserDefaultsKeys.downloadedLocalModels)
        }
    }

    private func completeDownload(tempLocation: URL) {
        guard let model = currentDownloadModel else { return }

        Task { @MainActor in
            do {
                let modelsDirectory = try getModelsDirectory()
                let destinationURL = modelsDirectory.appendingPathComponent("\(model.name).gguf")

                // Remove existing file if present
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }

                // Move downloaded file to final location
                try FileManager.default.moveItem(at: tempLocation, to: destinationURL)

                // Add to downloaded models
                let downloadedModel = DownloadedModel(
                    id: model.id,
                    info: model,
                    localPath: destinationURL.path,
                    downloadedAt: Date()
                )

                downloadedModels.append(downloadedModel)
                saveDownloadedModels()

                Logger.info("Successfully downloaded model: \(model.displayName)")

                // Show toast notification
                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Model '\(model.displayName)' downloaded successfully!",
                        style: .success,
                        duration: 3.0
                    )
                )

            } catch {
                Logger.error("Failed to save downloaded model: \(error.localizedDescription)")
                downloadError = error

                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Failed to save model: \(error.localizedDescription)",
                        style: .error,
                        duration: 3.0
                    )
                )
            }

            isDownloading = false
            currentDownloadModel = nil
            downloadProgress = 0
            resumeData = nil
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            completeDownload(tempLocation: location)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            if totalBytesExpectedToWrite > 0 {
                downloadProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if let error = error {
                // Check if cancelled with resume data
                if let nsError = error as NSError?,
                   nsError.code == NSURLErrorCancelled,
                   let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    self.resumeData = resumeData
                    Logger.info("Download paused, can be resumed")
                } else {
                    downloadError = error
                    Logger.error("Download failed: \(error.localizedDescription)")

                    NotificationCenter.default.post(
                        name: .showToast,
                        object: ToastMessage(
                            text: "Download failed: \(error.localizedDescription)",
                            style: .error,
                            duration: 3.0
                        )
                    )
                }

                isDownloading = false
                currentDownloadModel = nil
            }
        }
    }
}

// MARK: - Errors

enum ModelDownloadError: LocalizedError {
    case downloadInProgress
    case insufficientDiskSpace(required: UInt64, available: UInt64)
    case downloadFailed(String)
    case fileMoveFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadInProgress:
            return "A download is already in progress"
        case .insufficientDiskSpace(let required, let available):
            let requiredGB = Double(required) / 1_073_741_824
            let availableGB = Double(available) / 1_073_741_824
            return String(format: "Insufficient disk space. Required: %.1fGB, Available: %.1fGB", requiredGB, availableGB)
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .fileMoveFailed(let reason):
            return "Failed to save model: \(reason)"
        }
    }
}

// MARK: - FileManager Extension

extension FileManager {
    func availableCapacity(forPath path: String) throws -> Int64 {
        let attributes = try attributesOfFileSystem(forPath: path)
        return (attributes[.systemFreeSize] as? Int64) ?? 0
    }
}
