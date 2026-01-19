import Foundation
import AppKit
import LLM

/// Hardware architecture detection
enum HardwareArchitecture {
    case appleSilicon  // M1, M2, M3, etc.
    case intel
    case unknown
    
    static func detect() -> HardwareArchitecture {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        
        guard let machineString = machine else {
            return .unknown
        }
        
        // Apple Silicon Macs report "arm64"
        if machineString.contains("arm64") {
            return .appleSilicon
        } else if machineString.contains("x86_64") {
            return .intel
        }
        
        return .unknown
    }
    
    var isAppleSilicon: Bool {
        self == .appleSilicon
    }
    
    var displayName: String {
        switch self {
        case .appleSilicon:
            return "Apple Silicon"
        case .intel:
            return "Intel"
        case .unknown:
            return "Unknown"
        }
    }
    
    var performanceWarning: String? {
        switch self {
        case .intel:
            return NSLocalizedString("local.llm.intel.warning", comment: "Intel performance warning")
        case .unknown:
            return NSLocalizedString("local.llm.unknown.hardware.warning", comment: "Unknown hardware warning")
        case .appleSilicon:
            return nil
        }
    }
}

/// Service for local LLM inference using llama.cpp via LLM.swift
@MainActor
class LocalLLMService: AIServiceProtocol {
    static let shared = LocalLLMService()

    // MARK: - Public Properties
    
    /// Detected hardware architecture
    let hardwareArchitecture: HardwareArchitecture
    
    /// Whether the current hardware is optimal for local LLM
    var isOptimalHardware: Bool {
        hardwareArchitecture.isAppleSilicon
    }

    // MARK: - Private Properties

    private var llm: LLM?
    private var visionLLM: LLM?
    private var isModelLoaded = false
    private var isVisionModelLoaded = false
    private var currentModelPath: String?
    private var loadingTask: Task<Void, Error>?
    
    /// Timer for auto-unloading model after inactivity
    private var autoUnloadTimer: Timer?
    
    /// Last time the model was used for inference
    private var lastInferenceTime: Date?
    
    /// Auto-unload timeout in seconds (15 minutes)
    private let autoUnloadTimeout: TimeInterval = 15 * 60

    private let settings = SettingsManager.shared
    private let downloadManager = ModelDownloadManager.shared

    // MARK: - Initialization

    private init() {
        // Detect hardware on initialization
        hardwareArchitecture = HardwareArchitecture.detect()
        Logger.info("Detected hardware architecture: \(hardwareArchitecture.displayName)")
        
        // Log warning for non-optimal hardware
        if let warning = hardwareArchitecture.performanceWarning {
            Logger.warning("Hardware warning: \(warning)")
        }
        
        // Start auto-unload timer
        startAutoUnloadTimer()
    }
    
    deinit {
        autoUnloadTimer?.invalidate()
    }

    // MARK: - AIServiceProtocol

    func generateResponse(prompt: String) async throws -> String {
        // Update last inference time
        lastInferenceTime = Date()
        
        // Ensure model is loaded
        try await ensureModelLoaded()

        guard let llm = llm else {
            throw AIServiceError.modelNotDownloaded
        }

        // Add timeout protection
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.performInference(prompt: prompt, llm: llm)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(JoyaFixConstants.LocalLLM.inferenceTimeout * 1_000_000_000))
                throw AIServiceError.networkError(NSError(
                    domain: "LocalLLMService",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Inference timed out. The model may be too slow for this prompt."]
                ))
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw AIServiceError.emptyResponse
            }
            group.cancelAll()
            return result
        }
    }

    func describeImage(image: NSImage) async throws -> String {
        // Update last inference time
        lastInferenceTime = Date()
        
        // Check if vision model is available
        guard let visionModel = getVisionModel() else {
            throw AIServiceError.visionModelNotAvailable
        }

        // Ensure vision model is loaded
        try await ensureVisionModelLoaded(model: visionModel)

        guard let visionLLM = visionLLM else {
            throw AIServiceError.visionModelNotAvailable
        }

        // Convert NSImage to Data
        // Note: pngData is prepared for future vision model support
        guard let imageData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: imageData),
              let _ = bitmapImage.representation(using: .png, properties: [:]) else {
            throw AIServiceError.encodingError(NSError(
                domain: "LocalLLMService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"]
            ))
        }

        // Vision prompt
        let visionPrompt = "Describe this image with extreme detail for an AI image generator. Include style, color palette, lighting, and composition. Be concise yet vivid."

        // Add timeout protection
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                // Note: LLM.swift basic version may not support vision directly
                // For vision models like LLaVA, additional integration may be needed
                try await self.performInference(prompt: visionPrompt, llm: visionLLM)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(JoyaFixConstants.LocalLLM.inferenceTimeout * 1_000_000_000))
                throw AIServiceError.networkError(NSError(
                    domain: "LocalLLMService",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Vision inference timed out."]
                ))
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw AIServiceError.emptyResponse
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Model Management

    /// Loads a model for inference
    func loadModel(from path: String) async throws {
        // Check if already loading
        if let loadingTask = loadingTask {
            try await loadingTask.value
            return
        }

        // Pre-load RAM check with detailed diagnostics
        let ramCheckResult = checkRAMAvailability(forModelPath: path)
        
        switch ramCheckResult {
        case .sufficient:
            Logger.info("RAM check passed")
        case .insufficient(let required, let available):
            Logger.error("Insufficient RAM: required \(formatBytes(required)), available \(formatBytes(available))")
            
            // Show toast notification to user
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(
                    text: NSLocalizedString("local.llm.insufficient.ram", comment: "Close other apps to use local model"),
                    style: .warning,
                    duration: 5.0
                )
            )
            
            throw AIServiceError.insufficientMemory(required: required, available: available)
        case .criticallyLow(let available):
            Logger.error("System RAM critically low: \(formatBytes(available))")
            
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(
                    text: NSLocalizedString("local.llm.critical.ram", comment: "System memory critically low"),
                    style: .error,
                    duration: 5.0
                )
            )
            
            throw AIServiceError.insufficientMemory(required: JoyaFixConstants.LocalLLM.minimumRAMRequired, available: available)
        }

        // Check file exists
        guard FileManager.default.fileExists(atPath: path) else {
            throw AIServiceError.modelNotFound(path)
        }
        
        // Show Intel warning if applicable
        if let warning = hardwareArchitecture.performanceWarning {
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(
                    text: warning,
                    style: .warning,
                    duration: 4.0
                )
            )
        }

        loadingTask = Task {
            defer { loadingTask = nil }

            Logger.info("Loading local model from: \(path)")
            Logger.info("Hardware: \(hardwareArchitecture.displayName)")

            // Unload existing model
            unloadModel()

            // Create new LLM instance from file path
            let modelURL = URL(fileURLWithPath: path)
            llm = LLM(from: modelURL, template: .alpaca("You are a helpful AI assistant."))
            currentModelPath = path
            isModelLoaded = true
            lastInferenceTime = Date()

            Logger.info("Local model loaded successfully")
        }

        try await loadingTask!.value
    }

    /// Unloads the current model to free memory
    func unloadModel() {
        if llm != nil {
            llm = nil
            isModelLoaded = false
            currentModelPath = nil
            Logger.info("Local model unloaded - RAM freed")
        }
    }

    /// Unloads the vision model to free memory
    func unloadVisionModel() {
        if visionLLM != nil {
            visionLLM = nil
            isVisionModelLoaded = false
            Logger.info("Local vision model unloaded - RAM freed")
        }
    }
    
    /// Unloads all models to free maximum memory
    func unloadAllModels() {
        unloadModel()
        unloadVisionModel()
        Logger.info("All local models unloaded")
    }

    /// Checks if a model is currently loaded
    var isReady: Bool {
        isModelLoaded && llm != nil
    }

    /// Checks if a vision model is currently loaded
    var isVisionReady: Bool {
        isVisionModelLoaded && visionLLM != nil
    }
    
    // MARK: - RAM Management
    
    /// Result of RAM availability check
    private enum RAMCheckResult {
        case sufficient
        case insufficient(required: UInt64, available: UInt64)
        case criticallyLow(available: UInt64)
    }
    
    /// Checks RAM availability before loading a model
    private func checkRAMAvailability(forModelPath path: String) -> RAMCheckResult {
        let availableRAM = getAvailableRAM()
        let requiredRAM = getRequiredRAMForModel(atPath: path)
        
        Logger.info("RAM Check - Available: \(formatBytes(availableRAM)), Required: \(formatBytes(requiredRAM))")
        
        // Critical threshold: less than 1GB free
        let criticalThreshold: UInt64 = 1_073_741_824  // 1GB
        
        if availableRAM < criticalThreshold {
            return .criticallyLow(available: availableRAM)
        }
        
        // Add 20% safety buffer to required RAM
        let requiredWithBuffer = UInt64(Double(requiredRAM) * 1.2)
        
        if availableRAM < requiredWithBuffer {
            return .insufficient(required: requiredWithBuffer, available: availableRAM)
        }
        
        return .sufficient
    }
    
    /// Gets available RAM using host_statistics64
    private func getAvailableRAM() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            Logger.error("Failed to get VM statistics")
            return 0
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        
        // Available RAM = free + inactive (can be reclaimed) + purgeable
        let freePages = UInt64(stats.free_count)
        let inactivePages = UInt64(stats.inactive_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        
        let availableRAM = (freePages + inactivePages + purgeablePages) * pageSize
        
        Logger.info("RAM breakdown - Free: \(formatBytes(freePages * pageSize)), Inactive: \(formatBytes(inactivePages * pageSize)), Purgeable: \(formatBytes(purgeablePages * pageSize))")
        
        return availableRAM
    }
    
    /// Gets required RAM for a model based on file size or model info
    private func getRequiredRAMForModel(atPath path: String) -> UInt64 {
        // Try to find model info from registry
        for model in LocalModelRegistry.availableModels {
            if path.contains(model.name) {
                return model.requiredRAM
            }
        }
        
        // Fallback: estimate based on file size (typically 2x file size for GGUF models)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attrs[.size] as? UInt64 {
            return fileSize * 2
        }
        
        // Default minimum
        return JoyaFixConstants.LocalLLM.minimumRAMRequired
    }
    
    /// Format bytes to human-readable string
    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
    
    // MARK: - Auto-Unload Timer
    
    /// Starts the auto-unload timer that checks for inactivity
    private func startAutoUnloadTimer() {
        // Check every minute
        autoUnloadTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAutoUnload()
            }
        }
    }
    
    /// Checks if models should be auto-unloaded due to inactivity
    private func checkAutoUnload() {
        guard isModelLoaded || isVisionModelLoaded else {
            return  // No models loaded
        }
        
        guard let lastInference = lastInferenceTime else {
            // No inference ever done, unload if loaded for some reason
            if isModelLoaded || isVisionModelLoaded {
                Logger.info("Auto-unloading models (never used)")
                unloadAllModels()
            }
            return
        }
        
        let timeSinceLastInference = Date().timeIntervalSince(lastInference)
        
        if timeSinceLastInference >= autoUnloadTimeout {
            Logger.info("Auto-unloading models due to \(Int(timeSinceLastInference / 60)) minutes of inactivity")
            unloadAllModels()
            
            // Notify user
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(
                    text: NSLocalizedString("local.llm.auto.unloaded", comment: "Model auto-unloaded"),
                    style: .info,
                    duration: 3.0
                )
            )
        }
    }
    
    /// Resets the auto-unload timer (call when model is used)
    private func resetAutoUnloadTimer() {
        lastInferenceTime = Date()
    }

    // MARK: - Private Methods

    private func ensureModelLoaded() async throws {
        // Get selected model
        guard let selectedModel = settings.selectedLocalModel,
              let downloadedModel = downloadManager.getDownloadedModel(byId: selectedModel) else {
            throw AIServiceError.modelNotDownloaded
        }

        // Check if file still exists
        guard downloadedModel.exists else {
            throw AIServiceError.modelNotFound(downloadedModel.localPath)
        }

        // Check if already loaded with same model
        if isModelLoaded && currentModelPath == downloadedModel.localPath {
            resetAutoUnloadTimer()
            return
        }

        // Load model
        try await loadModel(from: downloadedModel.localPath)
    }

    private func ensureVisionModelLoaded(model: DownloadedModel) async throws {
        if isVisionModelLoaded && visionLLM != nil {
            resetAutoUnloadTimer()
            return
        }

        // Check RAM with detailed check
        let ramCheckResult = checkRAMAvailability(forModelPath: model.localPath)
        
        switch ramCheckResult {
        case .sufficient:
            break
        case .insufficient(let required, let available):
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(
                    text: NSLocalizedString("local.llm.insufficient.ram", comment: "Close other apps to use local model"),
                    style: .warning,
                    duration: 5.0
                )
            )
            throw AIServiceError.insufficientMemory(required: required, available: available)
        case .criticallyLow(let available):
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(
                    text: NSLocalizedString("local.llm.critical.ram", comment: "System memory critically low"),
                    style: .error,
                    duration: 5.0
                )
            )
            throw AIServiceError.insufficientMemory(required: model.info.requiredRAM, available: available)
        }

        // Check file exists
        guard model.exists else {
            throw AIServiceError.modelNotFound(model.localPath)
        }

        let modelURL = URL(fileURLWithPath: model.localPath)
        visionLLM = LLM(from: modelURL, template: .alpaca("You are a helpful AI assistant that can describe images."))
        isVisionModelLoaded = true
        lastInferenceTime = Date()

        Logger.info("Vision model loaded successfully")
    }

    private func performInference(prompt: String, llm: LLM) async throws -> String {
        // Update inference time
        resetAutoUnloadTimer()
        
        // Use LLM.swift's getCompletion method which returns a String
        // getCompletion handles input processing internally
        let response = await llm.getCompletion(from: prompt)

        let cleanedResponse = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        guard !cleanedResponse.isEmpty else {
            throw AIServiceError.emptyResponse
        }

        Logger.info("Local LLM inference completed: \(cleanedResponse.count) chars")
        return cleanedResponse
    }

    private func getVisionModel() -> DownloadedModel? {
        downloadManager.downloadedModels.first { $0.info.supportsVision }
    }
}

// MARK: - Hardware Detection Extension

extension LocalLLMService {
    /// Gets recommended models for the current hardware
    func getRecommendedModels() -> [LocalModelInfo] {
        switch hardwareArchitecture {
        case .appleSilicon:
            // All models work well on Apple Silicon
            return LocalModelRegistry.availableModels
        case .intel:
            // Recommend smaller models for Intel
            return LocalModelRegistry.availableModels.filter { $0.fileSize <= 2_500_000_000 }
        case .unknown:
            // Conservative recommendations
            return LocalModelRegistry.availableModels.filter { $0.fileSize <= 2_000_000_000 }
        }
    }
    
    /// Checks if a specific model is recommended for current hardware
    func isModelRecommended(_ model: LocalModelInfo) -> Bool {
        switch hardwareArchitecture {
        case .appleSilicon:
            return true  // All models recommended
        case .intel:
            // Only smaller models recommended for Intel
            return model.fileSize <= 2_500_000_000
        case .unknown:
            return model.fileSize <= 2_000_000_000
        }
    }
    
    /// Gets performance estimate for a model on current hardware
    func getPerformanceEstimate(for model: LocalModelInfo) -> String {
        switch hardwareArchitecture {
        case .appleSilicon:
            if model.fileSize <= 2_000_000_000 {
                return NSLocalizedString("local.llm.performance.fast", comment: "Fast performance")
            } else if model.fileSize <= 4_000_000_000 {
                return NSLocalizedString("local.llm.performance.good", comment: "Good performance")
            } else {
                return NSLocalizedString("local.llm.performance.moderate", comment: "Moderate performance")
            }
        case .intel:
            if model.fileSize <= 1_500_000_000 {
                return NSLocalizedString("local.llm.performance.moderate", comment: "Moderate performance")
            } else {
                return NSLocalizedString("local.llm.performance.slow", comment: "Slow performance")
            }
        case .unknown:
            return NSLocalizedString("local.llm.performance.unknown", comment: "Unknown performance")
        }
    }
}
