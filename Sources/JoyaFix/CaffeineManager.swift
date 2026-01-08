import Foundation
import IOKit.pwr_mgt
import Combine

/// Manages system sleep prevention (Caffeine Mode)
@MainActor
class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()
    
    @Published var isActive: Bool = false
    
    private var assertionID: IOPMAssertionID = 0
    private let assertionName = "JoyaFix Caffeine Mode" as CFString
    
    private init() {
        // Load saved state
        isActive = UserDefaults.standard.bool(forKey: "caffeineModeActive")
        if isActive {
            // Restore active state on init
            activate()
        }
    }
    
    /// Activates caffeine mode (prevents system sleep)
    func activate() {
        guard !isActive else { return }
        
        var assertionID: IOPMAssertionID = 0
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionName,
            &assertionID
        )
        
        if success == kIOReturnSuccess {
            self.assertionID = assertionID
            isActive = true
            UserDefaults.standard.set(true, forKey: "caffeineModeActive")
            Logger.info("☕ Caffeine mode activated")
        } else {
            Logger.error("Failed to activate caffeine mode: \(success)")
        }
    }
    
    /// Deactivates caffeine mode
    func deactivate() {
        guard isActive else { return }
        
        let success = IOPMAssertionRelease(assertionID)
        if success == kIOReturnSuccess {
            assertionID = 0
            isActive = false
            UserDefaults.standard.set(false, forKey: "caffeineModeActive")
            Logger.info("☕ Caffeine mode deactivated")
        } else {
            Logger.error("Failed to deactivate caffeine mode: \(success)")
        }
    }
    
    /// Toggles caffeine mode
    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }
    
    deinit {
        // Release assertion if still active (nonisolated context)
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }
}

