import Foundation
import Cocoa
import Sparkle

/// Manages app update checking and notifications
/// TODO: Migrate to SPUStandardUpdaterController for full Sparkle integration
/// Currently uses custom JSON-based update checking as a fallback
@MainActor
class UpdateManager {
    static let shared = UpdateManager()
    
    // MARK: - Configuration
    
    /// Sparkle updater controller (for future full integration)
    /// To fully integrate: Initialize SPUStandardUpdaterController in AppDelegate
    /// and connect it to the menu item "Check for Updates..."
    private var updaterController: SPUStandardUpdaterController?
    
    /// GitHub URL for version check (placeholder - replace with actual repo URL)
    private let versionCheckURL = "https://raw.githubusercontent.com/sassongal/JoyaFix/master/version.json"
    
    private init() {
        // Initialize Sparkle updater controller
        // Note: Full integration requires adding to Info.plist:
        // - SUFeedURL: URL to appcast.xml
        // - SUPublicEDSAKey: Public key for signing
        // For now, we keep the custom update checking as fallback
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
    
    // MARK: - Version Checking
    
    /// Checks for app updates asynchronously
    /// - Parameter completion: Called with update info if available, or nil if no update or error
    func checkForUpdates(completion: @escaping (UpdateInfo?) -> Void) {
        guard let url = URL(string: versionCheckURL) else {
            print("❌ Invalid version check URL")
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else {
                completion(nil)
                return
            }
            
            if let error = error {
                print("⚠️ Update check failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let data = data else {
                print("⚠️ Invalid response from update server")
                completion(nil)
                return
            }
            
            do {
                let updateInfo = try JSONDecoder().decode(UpdateInfo.self, from: data)
                
                // Compare versions - wrap in Task to safely access MainActor methods
                Task { @MainActor in
                    if self.isUpdateAvailable(localVersion: self.currentVersion, remoteVersion: updateInfo.version) {
                        print("✓ Update available: \(updateInfo.version)")
                        completion(updateInfo)
                    } else {
                        print("ℹ️ App is up to date (current: \(self.currentVersion))")
                        completion(nil)
                    }
                }
            } catch {
                print("❌ Failed to parse update info: \(error.localizedDescription)")
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    /// Cleans up old installation files before update
    /// This should be called before installing an update to prevent conflicts
    func cleanupOldInstallation() {
        let fileManager = FileManager.default
        
        // Clean up old cache files
        if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let joyaFixCache = cacheURL.appendingPathComponent("com.joyafix.app")
            if fileManager.fileExists(atPath: joyaFixCache.path) {
                try? fileManager.removeItem(at: joyaFixCache)
                Logger.info("Cleaned up old cache files")
            }
        }
        
        // Clean up old temporary files
        if let tempURL = fileManager.urls(for: .itemReplacementDirectory, in: .userDomainMask).first {
            let joyaFixTemp = tempURL.appendingPathComponent("JoyaFix")
            if fileManager.fileExists(atPath: joyaFixTemp.path) {
                try? fileManager.removeItem(at: joyaFixTemp)
                Logger.info("Cleaned up old temporary files")
            }
        }
        
        // Clean up old log files (keep only recent ones)
        if let logsURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let logsPath = logsURL.appendingPathComponent("Logs/com.joyafix.app")
            if let logFiles = try? fileManager.contentsOfDirectory(at: logsPath, includingPropertiesForKeys: [.creationDateKey]) {
                // Sort by creation date and remove old files (older than 30 days)
                let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
                for logFile in logFiles {
                    if let creationDate = try? logFile.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < thirtyDaysAgo {
                        try? fileManager.removeItem(at: logFile)
                    }
                }
            }
        }
        
        Logger.info("Cleanup completed before update")
    }
    
    /// Shows update available alert
    func showUpdateAlert(updateInfo: UpdateInfo) {
        // Clean up old files before showing update alert
        cleanupOldInstallation()
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.alert.title", comment: "Update Available")
        let message = String(format: NSLocalizedString("update.alert.message", comment: "Update message"), updateInfo.version, updateInfo.releaseNotes ?? "Bug fixes and improvements.")
        alert.informativeText = message + "\n\nWould you like to download it?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("update.alert.button", comment: "Download"))
        alert.addButton(withTitle: NSLocalizedString("update.alert.cancel", comment: "Later"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open download URL
            if let downloadURL = updateInfo.downloadURL,
               let url = URL(string: downloadURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// Shows "no update available" message
    func showNoUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.alert.no.update.title", comment: "You're Up to Date")
        alert.informativeText = NSLocalizedString("update.alert.no.update.message", comment: "No update message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
        alert.runModal()
    }
    
    // MARK: - Helper Methods
    
    /// Gets current app version from Info.plist
    private var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    /// Compares version strings to determine if update is available
    /// - Parameters:
    ///   - localVersion: Current app version (e.g., "1.0")
    ///   - remoteVersion: Remote version from server (e.g., "1.1")
    /// - Returns: True if remote version is newer
    private func isUpdateAvailable(localVersion: String, remoteVersion: String) -> Bool {
        let localComponents = localVersion.split(separator: ".").compactMap { Int($0) }
        let remoteComponents = remoteVersion.split(separator: ".").compactMap { Int($0) }
        
        // Compare version components
        let maxLength = max(localComponents.count, remoteComponents.count)
        
        for i in 0..<maxLength {
            let local = i < localComponents.count ? localComponents[i] : 0
            let remote = i < remoteComponents.count ? remoteComponents[i] : 0
            
            if remote > local {
                return true
            } else if remote < local {
                return false
            }
        }
        
        return false // Versions are equal
    }
}

// MARK: - Update Info Model

struct UpdateInfo: Codable {
    let version: String
    let releaseNotes: String?
    let downloadURL: String?
    
    enum CodingKeys: String, CodingKey {
        case version
        case releaseNotes = "release_notes"
        case downloadURL = "download_url"
    }
}

