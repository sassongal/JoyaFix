# JoyaFix Hotkey System

## Overview
JoyaFix uses a robust "Save & Rebind" hotkey system that ensures immediate application of new keyboard shortcuts with proper system priority.

## How It Works

### Priority System
JoyaFix uses the Carbon `RegisterEventHotKey` API which provides:
- **System-wide event handling** - Works even when JoyaFix is in the background
- **High priority** - JoyaFix hotkeys take precedence over focused applications
- **Immediate binding** - Changes apply instantly when saved

### Architecture

```
User Action → Local State → Save Button → UserDefaults → Rebind Hotkeys → System Registration
```

1. **User modifies settings** → Stored in local `@State` variables
2. **Click "Save Changes"** → Triggers save operation
3. **Save to UserDefaults** → Persists settings
4. **Rebind hotkeys** → Unregisters old keys, registers new ones
5. **System acknowledgment** → Sound plays, "Saved!" message appears

## Settings UI

### Local State Pattern
The Settings view uses local state to prevent immediate writes to UserDefaults:

```swift
@State private var localConvertKeyCode: UInt32
@State private var localConvertModifiers: UInt32
@State private var localOCRKeyCode: UInt32
@State private var localOCRModifiers: UInt32
@State private var hasUnsavedChanges: Bool
```

### Benefits:
- User can experiment with different key combinations
- Changes only applied when explicitly saved
- Can cancel/reset without affecting active hotkeys
- Clear visual feedback for unsaved state

### Visual Indicators

**Unsaved Changes:**
```
🟠 Unsaved changes
```
Appears when any setting is modified but not saved.

**Saved Confirmation:**
```
✅ Saved!
```
Appears for 2 seconds after successful save, with animation.

**Save Button States:**
- **Enabled** (blue, prominent) - When there are unsaved changes
- **Disabled** (gray) - When no changes to save

## Hotkey Rebinding Process

### `HotkeyManager.rebindHotkeys()`

The rebinding process follows these steps:

```swift
func rebindHotkeys() -> (convertSuccess: Bool, ocrSuccess: Bool) {
    // 1. Unregister all existing hotkeys
    unregisterHotkey()

    // 2. Small delay for system processing
    usleep(50000) // 50ms

    // 3. Register new hotkeys with current settings
    let convertSuccess = registerHotkey()
    let ocrSuccess = registerOCRHotkey()

    // 4. Play success sound and report results
    if convertSuccess && ocrSuccess {
        SoundManager.shared.playSuccess()
    }

    return (convertSuccess, ocrSuccess)
}
```

### Unregistration

```swift
func unregisterHotkey() {
    // Unregister text conversion hotkey
    if let eventHotKeyRef = eventHotKeyRef {
        UnregisterEventHotKey(eventHotKeyRef)
        self.eventHotKeyRef = nil
    }

    // Unregister OCR hotkey
    if let ocrHotKeyRef = ocrHotKeyRef {
        UnregisterEventHotKey(ocrHotKeyRef)
        self.ocrHotKeyRef = nil
    }

    // Remove event handler
    if let eventHandler = eventHandler {
        RemoveEventHandler(eventHandler)
        self.eventHandler = nil
    }
}
```

### Registration

Both hotkeys are registered using the same event handler but different IDs:

```swift
// Hotkey signatures
private let hotkeyID = EventHotKeyID(signature: OSType(0x4A4F5941), id: 1)  // 'JOYA'
private let ocrHotkeyID = EventHotKeyID(signature: OSType(0x4F435231), id: 2) // 'OCR1'

// Shared event handler
let status = InstallEventHandler(
    GetApplicationEventTarget(),
    { (nextHandler, event, userData) -> OSStatus in
        var hotkeyID = EventHotKeyID()
        GetEventParameter(event, ...)

        // Dispatch based on ID
        if hotkeyID.id == 1 {
            HotkeyManager.shared.hotkeyPressed()
        } else if hotkeyID.id == 2 {
            HotkeyManager.shared.ocrHotkeyPressed()
        }

        return noErr
    },
    ...
)
```

## Error Handling

### Registration Failures

If a hotkey fails to register, the system provides detailed error messages:

```
❌ Failed to register conversion hotkey: Hotkey already registered (duplicate)
   Attempted: ⌘⌥K
   This key combination may be reserved by the system or another app
```

### Common Error Codes:
- `-9850`: Hotkey already registered (duplicate)
- `-9879`: Invalid hotkey parameters
- `-50`: Parameter error
- Other: `Error code N`

### Handling Failed Registration:

1. **Check system shortcuts:**
   - System Preferences → Keyboard → Shortcuts
   - Look for conflicting shortcuts

2. **Try different combination:**
   - Use modifiers (Cmd, Option, Shift, Control)
   - Avoid single-key shortcuts (always require modifiers)

3. **Reserved combinations:**
   - Cmd+Tab, Cmd+Space, etc. are reserved by macOS
   - Some apps register global hotkeys (Spotlight, Alfred, etc.)

## User Flow

### Changing Hotkeys

1. **Open Settings** (Right-click menu → Settings)
2. **Click hotkey button** to start recording
3. **Press desired key combination** (must include modifier)
4. **Repeat for other hotkey** if needed
5. **Click "Save Changes"** button
6. **Hear success sound** and see "Saved!" message
7. **Hotkeys immediately active**

### Visual Feedback:

**Recording State:**
```
┌─────────────────────────────────┐
│ Press your key combination...   │ (Blue border, highlighted)
└─────────────────────────────────┘
```

**Recorded State:**
```
┌─────────────────────────────────┐
│         ⌘⌥K                      │ (Gray border, normal)
└─────────────────────────────────┘
```

### Unsaved Changes Flow:

```
1. Click hotkey button → Recording
2. Press ⌘⌥T → Shows "⌘⌥T"
3. "Unsaved changes" indicator appears (🟠)
4. Save button becomes enabled (blue)
5. Click "Save Changes"
6. Settings saved to UserDefaults
7. Hotkeys rebound immediately
8. "Saved!" message appears (✅)
9. Success sound plays
10. "Saved!" fades after 2 seconds
```

## Default Hotkeys

### Text Conversion
- **Default**: `⌘⌥K` (Cmd + Option + K)
- **Action**: Convert selected text between Hebrew and English keyboards

### OCR Screen Capture
- **Default**: `⌘⌥X` (Cmd + Option + X)
- **Action**: Capture screen region and extract text

### Modifying Defaults

The `resetToDefaults()` function restores original settings:

```swift
localConvertKeyCode = UInt32(kVK_ANSI_K)      // K
localConvertModifiers = UInt32(cmdKey | optionKey)  // Cmd+Option

localOCRKeyCode = UInt32(kVK_ANSI_X)          // X
localOCRModifiers = UInt32(cmdKey | optionKey)      // Cmd+Option
```

## Technical Implementation

### Settings Persistence

```swift
// SettingsManager saves to UserDefaults
private enum Keys {
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let ocrHotkeyKeyCode = "ocrHotkeyKeyCode"
    static let ocrHotkeyModifiers = "ocrHotkeyModifiers"
}

@Published var hotkeyKeyCode: UInt32 {
    didSet {
        UserDefaults.standard.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode)
    }
}
```

### Immediate Rebinding

When "Save Changes" is clicked:

```swift
private func saveChanges() {
    // 1. Save to UserDefaults (via SettingsManager)
    settings.hotkeyKeyCode = localConvertKeyCode
    settings.hotkeyModifiers = localConvertModifiers
    // ... other settings

    // 2. Rebind hotkeys immediately
    let result = HotkeyManager.shared.rebindHotkeys()

    // 3. Visual feedback
    hasUnsavedChanges = false
    showSavedMessage = true

    // 4. Hide "Saved!" after 2 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        showSavedMessage = false
    }
}
```

### Priority Guarantee

The Carbon `RegisterEventHotKey` API ensures:

1. **System-wide registration** - Hotkey works regardless of active app
2. **Event handler priority** - JoyaFix receives event before focused app
3. **Immediate effect** - No app restart required

### Event Flow:

```
User presses ⌘⌥K
    ↓
macOS detects hotkey
    ↓
Carbon event handler triggered
    ↓
HotkeyManager.hotkeyPressed() called
    ↓
Text conversion executes
```

## Troubleshooting

### Hotkeys Not Working

1. **Check Accessibility Permissions:**
   ```
   System Preferences → Security & Privacy → Privacy → Accessibility
   Enable: JoyaFix
   ```

2. **Verify Registration:**
   - Run `./test.sh` to see console output
   - Look for "✓ Conversion hotkey registered: ⌘⌥K"
   - Check for error messages

3. **Conflict Resolution:**
   - If hotkey fails to register, try different combination
   - Check System Preferences → Keyboard → Shortcuts
   - Disable conflicting system shortcuts

### Changes Not Saving

1. **Ensure you click "Save Changes"** button
2. **Check for error messages** in console
3. **Verify UserDefaults** (settings should persist after app restart)

### Sound Not Playing

1. **Check "Play sound on convert"** setting is enabled
2. **Verify success.wav** exists in app bundle:
   ```bash
   ls build/JoyaFix.app/Contents/Resources/success.wav
   ```
3. **Test sound file**:
   ```bash
   afplay success.wav
   ```

## Best Practices

### Choosing Hotkeys

✅ **Good combinations:**
- `⌘⌥K` - Cmd + Option + K
- `⌃⌥T` - Control + Option + T
- `⌘⇧X` - Cmd + Shift + X

❌ **Avoid:**
- Single keys without modifiers (A, K, etc.)
- System reserved (⌘Space, ⌘Tab, ⌘Q)
- Common app shortcuts (⌘C, ⌘V, ⌘S)

### Testing New Hotkeys

1. Record new combination in Settings
2. Click "Save Changes"
3. Test immediately by pressing the hotkey
4. If it doesn't work, try a different combination
5. Check console for error messages

## Console Output Examples

### Successful Rebind:
```
🔄 Rebinding hotkeys...
✓ Conversion hotkey registered: ⌘⌥K
✓ OCR hotkey registered: ⌘⌥X
✓ All hotkeys rebound successfully
```

### Failed Rebind:
```
🔄 Rebinding hotkeys...
❌ Failed to register conversion hotkey: Hotkey already registered (duplicate)
   Attempted: ⌘⌥K
   This key combination may be reserved by the system or another app
✓ OCR hotkey registered: ⌘⌥X
⚠️ Some hotkeys failed to rebind
```

### Using Hotkey:
```
🔥 Hotkey pressed! Converting text...
Original text: vhuo
Converted text: שלום
✓ Settings saved and hotkeys rebound successfully
```

## Summary

The JoyaFix hotkey system provides:

- ✅ **Immediate application** of new shortcuts
- ✅ **System-wide priority** over other apps
- ✅ **Visual feedback** for changes and saves
- ✅ **Error handling** with helpful messages
- ✅ **Sound confirmation** on successful save
- ✅ **Unsaved changes tracking** prevents accidental loss
- ✅ **Robust rebinding** with proper cleanup and registration

This ensures users can confidently configure their hotkeys knowing they'll work immediately and reliably.
