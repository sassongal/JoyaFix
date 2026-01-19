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

        Logger.info("Starting download for model: \(model.displayName)")
        Logger.info("Download URL: \(model.downloadURL)")

        // Check and create models directory
        let modelsDirectory: URL
        do {
            modelsDirectory = try getModelsDirectory()
            Logger.info("Models directory path: \(modelsDirectory.path)")
        } catch {
            Logger.error("Failed to get/create models directory: \(error.localizedDescription)")
            throw ModelDownloadError.fileMoveFailed("Cannot access models directory: \(error.localizedDescription)")
        }

        // Check available disk space
        let availableSpace: Int64
        do {
            availableSpace = try FileManager.default.availableCapacity(forPath: modelsDirectory.path)
            Logger.info("Available disk space: \(ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file))")
        } catch {
            Logger.error("Failed to check disk space: \(error.localizedDescription)")
            throw ModelDownloadError.downloadFailed("Cannot check disk space: \(error.localizedDescription)")
        }

        guard availableSpace > Int64(model.fileSize) + 500_000_000 else {  // 500MB buffer
            Logger.error("Insufficient disk space. Required: \(model.fileSizeFormatted), Available: \(ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file))")
            throw ModelDownloadError.insufficientDiskSpace(required: model.fileSize, available: UInt64(availableSpace))
        }

        isDownloading = true
        currentDownloadModel = model
        downloadProgress = 0
        downloadError = nil

        // Resume download if possible
        if let resumeData = resumeData {
            Logger.info("Resuming previous download...")
            downloadTask = urlSession.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
        } else {
            Logger.info("Starting fresh download...")
            downloadTask = urlSession.downloadTask(with: model.downloadURL)
        }

        // Observe progress
        progressObservation = downloadTask?.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.downloadProgress = progress.fractionCompleted
            }
        }

        downloadTask?.resume()
        Logger.info("Download task started")
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
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.error("Could not find Application Support directory")
            throw ModelDownloadError.fileMoveFailed("Cannot find Application Support directory")
        }

        let modelsDir = appSupport.appendingPathComponent(JoyaFixConstants.FilePaths.localModelsDirectory)
        Logger.info("Models directory path: \(modelsDir.path)")

        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            Logger.info("Creating models directory...")
            do {
                try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true, attributes: nil)
                Logger.info("Models directory created successfully")
            } catch {
                Logger.error("Failed to create models directory: \(error.localizedDescription)")
                throw ModelDownloadError.fileMoveFailed("Cannot create models directory: \(error.localizedDescription)")
            }
        } else {
            Logger.info("Models directory already exists")
        }

        // Verify directory is writable
        if !FileManager.default.isWritableFile(atPath: modelsDir.path) {
            Logger.error("Models directory is not writable: \(modelsDir.path)")
            throw ModelDownloadError.fileMoveFailed("Models directory is not writable")
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
    
    // MARK: - Model Discovery
    
    /// Refreshes and discovers local models from multiple sources
    /// 1. Ollama installed models (via /api/tags)
    /// 2. External GGUF files in common directories
    @Published var isScanning: Bool = false
    @Published var lastScanDate: Date?
    
    /// Refreshes local models by scanning Ollama and file system
    func refreshLocalModels() async {
        guard !isScanning else { return }
        
        isScanning = true
        defer { isScanning = false }
        
        Logger.info("Starting local model discovery...")
        
        var discoveredModels: [DownloadedModel] = []
        
        // Keep existing downloaded models (source == .downloaded)
        let existingDownloaded = downloadedModels.filter { $0.source == .downloaded && $0.exists }
        discoveredModels.append(contentsOf: existingDownloaded)
        
        // 1. Discover Ollama models
        let ollamaModels = await discoverOllamaModels()
        discoveredModels.append(contentsOf: ollamaModels)
        
        // 2. Discover external GGUF files
        let externalModels = await discoverExternalGGUFModels()
        discoveredModels.append(contentsOf: externalModels)
        
        // Update the list (remove duplicates by ID)
        var uniqueModels: [String: DownloadedModel] = [:]
        for model in discoveredModels {
            // Prefer downloaded over discovered
            if let existing = uniqueModels[model.id] {
                if existing.source == .downloaded {
                    continue // Keep downloaded version
                }
            }
            uniqueModels[model.id] = model
        }
        
        downloadedModels = Array(uniqueModels.values).sorted { $0.downloadedAt > $1.downloadedAt }
        saveDownloadedModels()
        
        lastScanDate = Date()
        
        Logger.info("Model discovery complete. Found \(downloadedModels.count) models")
        
        // Show toast
        NotificationCenter.default.post(
            name: .showToast,
            object: ToastMessage(
                text: "Found \(downloadedModels.count) models",
                style: .success,
                duration: 2.0
            )
        )
    }
    
    /// Discovers models installed in Ollama
    private func discoverOllamaModels() async -> [DownloadedModel] {
        var models: [DownloadedModel] = []
        
        do {
            let ollamaModels = try await OllamaService.shared.fetchAvailableModels()
            
            for ollamaModel in ollamaModels {
                // Create LocalModelInfo for Ollama model
                let modelInfo = LocalModelInfo(
                    id: "ollama-\(ollamaModel.name)",
                    name: ollamaModel.name,
                    displayName: ollamaModel.displayName,
                    description: "Ollama model: \(ollamaModel.details?.family ?? "Unknown family")",
                    downloadURL: URL(string: "ollama://\(ollamaModel.name)")!,  // Placeholder URL
                    fileSize: UInt64(ollamaModel.size ?? 0),
                    requiredRAM: UInt64(ollamaModel.size ?? 0) * 2,  // Estimate: 2x file size
                    supportsVision: ollamaModel.supportsVision,
                    quantization: ollamaModel.details?.quantizationLevel ?? "Unknown",
                    contextLength: 4096  // Default
                )
                
                let downloadedModel = DownloadedModel(
                    id: "ollama-\(ollamaModel.name)",
                    info: modelInfo,
                    localPath: "",  // Ollama manages the path
                    downloadedAt: Date(),
                    isExternal: true,
                    source: .ollama,
                    ollamaModelName: ollamaModel.name
                )
                
                models.append(downloadedModel)
            }
            
            Logger.info("Discovered \(models.count) Ollama models")
            
        } catch {
            Logger.warning("Failed to discover Ollama models: \(error.localizedDescription)")
        }
        
        return models
    }
    
    /// Discovers GGUF model files in common directories
    private func discoverExternalGGUFModels() async -> [DownloadedModel] {
        var models: [DownloadedModel] = []
        
        // Common directories to scan
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let searchPaths = [
            homeDir.appendingPathComponent(".ollama/models"),
            homeDir.appendingPathComponent("Models"),
            homeDir.appendingPathComponent("AI-Models"),
            homeDir.appendingPathComponent("LLM-Models"),
            homeDir.appendingPathComponent("Downloads")  // Check Downloads for GGUF files
        ]
        
        for searchPath in searchPaths {
            guard FileManager.default.fileExists(atPath: searchPath.path) else {
                continue
            }
            
            // Check if we have read access (sandbox consideration)
            guard FileManager.default.isReadableFile(atPath: searchPath.path) else {
                Logger.warning("Cannot read directory (sandbox): \(searchPath.path)")
                continue
            }
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: searchPath,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                
                for fileURL in contents where fileURL.pathExtension.lowercased() == "gguf" {
                    // Get file attributes
                    let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    let fileSize = UInt64(attributes.fileSize ?? 0)
                    
                    // Create model info from file
                    let fileName = fileURL.deletingPathExtension().lastPathComponent
                    let modelId = "external-\(fileName)"
                    
                    // Skip if already tracked
                    if downloadedModels.contains(where: { $0.localPath == fileURL.path }) {
                        continue
                    }
                    
                    // Detect if it's a vision model from name
                    let supportsVision = ["llava", "bakllava", "moondream"].contains { fileName.lowercased().contains($0) }
                    
                    let modelInfo = LocalModelInfo(
                        id: modelId,
                        name: fileName,
                        displayName: formatModelName(fileName),
                        description: "External GGUF model found at: \(searchPath.lastPathComponent)",
                        downloadURL: fileURL,  // Local file URL
                        fileSize: fileSize,
                        requiredRAM: fileSize * 2,  // Estimate
                        supportsVision: supportsVision,
                        quantization: extractQuantization(from: fileName),
                        contextLength: 4096
                    )
                    
                    let downloadedModel = DownloadedModel(
                        id: modelId,
                        info: modelInfo,
                        localPath: fileURL.path,
                        downloadedAt: Date(),
                        isExternal: true,
                        source: .external,
                        ollamaModelName: nil
                    )
                    
                    models.append(downloadedModel)
                    Logger.info("Found external GGUF: \(fileName)")
                }
                
            } catch {
                Logger.warning("Error scanning \(searchPath.path): \(error.localizedDescription)")
            }
        }
        
        Logger.info("Discovered \(models.count) external GGUF models")
        return models
    }
    
    /// Formats a model filename into a display name
    private func formatModelName(_ filename: String) -> String {
        var name = filename
        
        // Remove common suffixes
        let suffixes = ["-gguf", "_gguf", ".gguf", "-q4_k_m", "-q4_k", "-q5_k_m", "-q5_k", "-q8_0", "-f16"]
        for suffix in suffixes {
            if name.lowercased().hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
            }
        }
        
        // Replace separators with spaces
        name = name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        
        // Capitalize words
        return name.capitalized
    }
    
    /// Extracts quantization info from filename
    private func extractQuantization(from filename: String) -> String {
        let patterns = ["q4_k_m", "q4_k", "q5_k_m", "q5_k", "q8_0", "f16", "q2_k", "q3_k"]
        let lowerName = filename.lowercased()
        
        for pattern in patterns {
            if lowerName.contains(pattern) {
                return pattern.uppercased()
            }
        }
        
        return "Unknown"
    }

    // MARK: - Integrity Verification
    
    /// Verifies that the downloaded file size is within acceptable tolerance
    private func verifyFileSize(expected: UInt64, actual: UInt64, tolerance: Double, tempLocation: URL) throws {
        // Calculate tolerance range
        let lowerBound = UInt64(Double(expected) * (1.0 - tolerance))
        let upperBound = UInt64(Double(expected) * (1.0 + tolerance))
        
        Logger.info("File size verification: expected \(expected) bytes (±\(Int(tolerance * 100))%), actual \(actual) bytes")
        Logger.info("Acceptable range: \(lowerBound) - \(upperBound) bytes")
        
        guard actual >= lowerBound && actual <= upperBound else {
            Logger.error("File size mismatch! Expected: \(expected), Actual: \(actual)")
            
            // Delete the corrupted temp file
            try? FileManager.default.removeItem(at: tempLocation)
            Logger.info("Deleted corrupted temp file")
            
            // Show error toast with clear message
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(
                    text: NSLocalizedString("download.corrupted.retry", comment: "Download corrupted. Please try again."),
                    style: .error,
                    duration: 5.0
                )
            )
            
            throw ModelDownloadError.fileSizeMismatch(expected: expected, actual: actual)
        }
        
        Logger.info("File size verification passed")
    }
    
    /// Verifies the SHA256 checksum of the downloaded file
    private func verifyChecksum(expected: String, fileURL: URL) async throws {
        Logger.info("Starting SHA256 checksum verification...")
        
        // Compute checksum asynchronously to avoid blocking main thread
        let actualChecksum = try await computeSHA256(for: fileURL)
        
        Logger.info("Expected checksum: \(expected)")
        Logger.info("Actual checksum: \(actualChecksum)")
        
        guard actualChecksum.lowercased() == expected.lowercased() else {
            Logger.error("Checksum mismatch!")
            
            // Delete the corrupted file
            try? FileManager.default.removeItem(at: fileURL)
            Logger.info("Deleted corrupted file")
            
            // Show error toast
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(
                    text: NSLocalizedString("download.verification.corrupted", comment: "Download corrupted"),
                    style: .error,
                    duration: 5.0
                )
            )
            
            throw ModelDownloadError.checksumMismatch(expected: expected, actual: actualChecksum)
        }
        
        Logger.info("Checksum verification passed")
    }
    
    /// Computes SHA256 hash of a file
    private func computeSHA256(for fileURL: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileHandle = try FileHandle(forReadingFrom: fileURL)
                    defer { try? fileHandle.close() }
                    
                    var hasher = SHA256Hasher()
                    let bufferSize = 1024 * 1024  // 1MB buffer for large files
                    
                    while autoreleasepool(invoking: {
                        guard let data = try? fileHandle.read(upToCount: bufferSize), !data.isEmpty else {
                            return false
                        }
                        hasher.update(data: data)
                        return true
                    }) {}
                    
                    let hash = hasher.finalize()
                    continuation.resume(returning: hash)
                } catch {
                    continuation.resume(throwing: ModelDownloadError.verificationFailed("Failed to compute checksum: \(error.localizedDescription)"))
                }
            }
        }
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
        guard let model = currentDownloadModel else {
            Logger.error("completeDownload called but no currentDownloadModel set")
            return
        }

        Logger.info("Download completed for: \(model.displayName)")
        Logger.info("Temp file location: \(tempLocation.path)")

        Task { @MainActor in
            do {
                // Get and verify models directory exists
                let modelsDirectory = try getModelsDirectory()
                Logger.info("Models directory: \(modelsDirectory.path)")

                // Double-check directory exists (create if needed)
                if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
                    Logger.info("Models directory doesn't exist, creating...")
                    try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
                    Logger.info("Models directory created successfully")
                }

                let destinationURL = modelsDirectory.appendingPathComponent("\(model.name).gguf")
                Logger.info("Destination path: \(destinationURL.path)")

                // Verify temp file exists
                guard FileManager.default.fileExists(atPath: tempLocation.path) else {
                    Logger.error("Temp file not found at: \(tempLocation.path)")
                    throw ModelDownloadError.fileMoveFailed("Downloaded file not found")
                }

                // Get temp file size for verification
                let attrs = try FileManager.default.attributesOfItem(atPath: tempLocation.path)
                guard let actualFileSize = attrs[.size] as? UInt64 else {
                    Logger.error("Could not determine downloaded file size")
                    throw ModelDownloadError.verificationFailed("Could not determine file size")
                }
                
                Logger.info("Downloaded file size: \(ByteCountFormatter.string(fromByteCount: Int64(actualFileSize), countStyle: .file))")
                
                // === INTEGRITY VERIFICATION ===
                // Verify file size is within acceptable tolerance
                try verifyFileSize(expected: model.fileSize, actual: actualFileSize, tolerance: model.fileSizeTolerance, tempLocation: tempLocation)
                
                // Verify SHA256 checksum if available
                if let expectedChecksum = model.sha256Checksum {
                    try await verifyChecksum(expected: expectedChecksum, fileURL: tempLocation)
                }
                
                Logger.info("Download integrity verification passed!")

                // Remove existing file if present
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    Logger.info("Removing existing file at destination...")
                    try FileManager.default.removeItem(at: destinationURL)
                }

                // Move downloaded file to final location
                Logger.info("Moving file to final destination...")
                try FileManager.default.moveItem(at: tempLocation, to: destinationURL)

                // Verify file was moved successfully
                guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                    Logger.error("File move appeared to succeed but file not found at destination")
                    throw ModelDownloadError.fileMoveFailed("File not found after move")
                }

                Logger.info("File moved successfully!")

                // Add to downloaded models
                let downloadedModel = DownloadedModel(
                    id: model.id,
                    info: model,
                    localPath: destinationURL.path,
                    downloadedAt: Date()
                )

                downloadedModels.append(downloadedModel)
                saveDownloadedModels()

                Logger.info("Successfully downloaded and saved model: \(model.displayName)")

                // Show toast notification
                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Model '\(model.displayName)' downloaded successfully!",
                        style: .success,
                        duration: 3.0
                    )
                )

            } catch let error as ModelDownloadError {
                Logger.error("ModelDownloadError: \(error.localizedDescription ?? "Unknown")")
                downloadError = error

                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Failed to save model: \(error.localizedDescription ?? "Unknown error")",
                        style: .error,
                        duration: 5.0
                    )
                )
            } catch {
                Logger.error("Failed to save downloaded model: \(error.localizedDescription)")
                Logger.error("Error type: \(type(of: error))")
                downloadError = error

                NotificationCenter.default.post(
                    name: .showToast,
                    object: ToastMessage(
                        text: "Failed to save model: \(error.localizedDescription)",
                        style: .error,
                        duration: 5.0
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
    case fileSizeMismatch(expected: UInt64, actual: UInt64)
    case checksumMismatch(expected: String, actual: String)
    case verificationFailed(String)

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
        case .fileSizeMismatch(let expected, let actual):
            let expectedMB = Double(expected) / 1_048_576
            let actualMB = Double(actual) / 1_048_576
            return String(format: NSLocalizedString("download.verification.failed", comment: "Download verification failed") + " Expected: %.1fMB, Actual: %.1fMB", expectedMB, actualMB)
        case .checksumMismatch(let expected, let actual):
            return "Checksum verification failed. Expected: \(expected.prefix(16))..., Got: \(actual.prefix(16))..."
        case .verificationFailed(let reason):
            return NSLocalizedString("download.verification.corrupted", comment: "Downloaded file corrupted") + " \(reason)"
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

// MARK: - SHA256 Hasher

import CommonCrypto

/// Simple SHA256 hasher wrapper for file integrity verification
struct SHA256Hasher {
    private var context = CC_SHA256_CTX()
    
    init() {
        CC_SHA256_Init(&context)
    }
    
    mutating func update(data: Data) {
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(buffer.count))
        }
    }
    
    mutating func finalize() -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
