import Foundation
import Cocoa

/// Manages app update checking and notifications
@MainActor
class UpdateManager {
    static let shared = UpdateManager()
    
    // MARK: - Configuration
    
    /// GitHub URL for version check (placeholder - replace with actual repo URL)
    private let versionCheckURL = "https://raw.githubusercontent.com/sassongal/JoyaFix/main/version.json"
    
    private init() {}
    
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
                
                // Compare versions
                if self.isUpdateAvailable(localVersion: self.currentVersion, remoteVersion: updateInfo.version) {
                    print("✓ Update available: \(updateInfo.version)")
                    DispatchQueue.main.async {
                        completion(updateInfo)
                    }
                } else {
                    print("ℹ️ App is up to date (current: \(self.currentVersion))")
                    DispatchQueue.main.async {
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
    
    /// Shows update available alert
    func showUpdateAlert(updateInfo: UpdateInfo) {
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

