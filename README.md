# JoyaFix 🇮🇱

**Your Ultimate Mac Utility** - Smart text conversion, OCR, snippets, and clipboard management all in one powerful app.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Installation & Building](#installation--building)
- [Usage Guide](#usage-guide)
- [Troubleshooting](#troubleshooting)
- [Technical Details](#technical-details)
- [Development](#development)

---

## Overview

JoyaFix is a professional macOS utility application that enhances your workflow with intelligent text conversion, OCR capabilities, text snippets, and advanced clipboard management. Built with SwiftUI and AppKit, it provides a native macOS experience with modern UI/UX.

### Key Highlights

- ✅ **Smart Text Conversion** - Instantly convert between Hebrew and English keyboard layouts
- ✅ **Cloud & Local OCR** - Extract text from any screen region using Gemini AI or local Vision framework
- ✅ **Text Snippets** - Auto-expand shortcuts into full text (e.g., `!mail` → `gal@joyatech.com`)
- ✅ **Advanced Clipboard History** - Rich text support, pinning, search, and paste as plain text
- ✅ **Keyboard Cleaner Mode** - Lock keyboard to prevent accidental input
- ✅ **Native macOS Design** - Beautiful blur effects, dark mode support, and smooth animations

---

## Features

### 1. Smart Text Conversion (Hebrew ↔ English)

**Hotkey:** `⌘⌥K` (default, customizable)

- **Automatic Detection** - Intelligently detects if text was typed in the wrong keyboard layout
- **Bidirectional Conversion** - Converts English→Hebrew and Hebrew→English seamlessly
- **Uppercase Support** - Handles CAPSLOCK and Shift correctly
- **Rich Text Preservation** - Maintains formatting (colors, fonts, bold) when converting
- **Instant Paste** - Optionally deletes original text and pastes converted version automatically
- **Success Sound** - Optional audio feedback on successful conversion

**Example:**
```
Input:  "shalom" (typed in English keyboard)
Output: "שלום" (converted to Hebrew layout)

Input:  "שלום" (typed in Hebrew keyboard)
Output: "shalom" (converted to English layout)
```

### 2. Smart OCR (Optical Character Recognition)

**Hotkey:** `⌘⌥X` (default, customizable)

- **Multi-Monitor Support** - Works seamlessly across all connected displays
- **Cloud OCR (Gemini 1.5 Flash)** - High-accuracy text extraction using Google's Gemini AI
- **Local OCR (Vision Framework)** - Fast, offline text recognition using Apple's Vision framework
- **Automatic Fallback** - Falls back to local OCR if cloud OCR fails
- **OCR History** - Saves all extracted text with preview images
- **Screen Selection** - Drag to select region, press ENTER to confirm, ESC to cancel

**Workflow:**
1. Press `⌘⌥X` to start OCR
2. Drag to select screen region
3. Press ENTER to confirm or ESC to cancel
4. Text is extracted, saved to history, and copied to clipboard

### 3. Text Snippets & Auto-Expansion

**Feature:** Type shortcuts that automatically expand into full text

- **Custom Triggers** - Define your own shortcuts (e.g., `!mail`, `!sig`)
- **Global Expansion** - Works in any application
- **Instant Replacement** - Deletes trigger and pastes content automatically
- **Easy Management** - Add, edit, delete snippets in Settings

**Example:**
```
Type:  "!mail"
Result: "gal@joyatech.com" (trigger deleted, content pasted)
```

### 4. Advanced Clipboard History

**Access:** Click menubar icon or use `⌘1-9` shortcuts

- **Rich Text Support** - Preserves formatting from Pages, Word, web content
- **Pinning** - Pin important items to keep them at the top
- **Search** - Quickly find items in history
- **Paste as Plain Text** - Hold Shift/Option while clicking to paste without formatting
- **Keyboard Shortcuts** - `⌘1` through `⌘9` for quick access
- **Auto-Save** - History persists between app launches

### 5. Keyboard Cleaner Mode

**Hotkey:** `⌘⌥L` (default)

- **Lock Keyboard** - Prevents all keyboard input
- **Visual Indicator** - Shows overlay when keyboard is locked
- **Unlock** - Press `⌘⌥L` again or hold ESC for 3 seconds
- **Perfect for Cleaning** - Clean your keyboard without triggering actions

---

## Architecture

### Technology Stack

- **SwiftUI** - Modern declarative UI framework
- **AppKit** - Native macOS window and menu management
- **Carbon Events** - Global hotkey registration (high priority, system-wide)
- **Vision Framework** - Local OCR text recognition
- **CoreGraphics** - Screen capture and image processing
- **Keychain Services** - Secure API key storage

### Core Components

```
JoyaFix/
├── JoyaFixApp.swift              # Main app entry point (SwiftUI App)
├── AppDelegate                   # NSApplicationDelegate for menubar integration
├── TextConverter.swift           # Hebrew ↔ English conversion logic
├── HotkeyManager.swift           # Global hotkey registration (Carbon Events)
├── ScreenCaptureManager.swift    # OCR screen capture (@MainActor isolated)
├── ClipboardHistoryManager.swift # Clipboard monitoring and history
├── InputMonitor.swift            # Global keyboard monitoring for snippets
├── SnippetManager.swift          # Snippet CRUD operations
├── PermissionManager.swift       # System permission checks
├── KeychainHelper.swift          # Secure API key storage
├── SettingsManager.swift         # User settings persistence
└── OCRHistoryManager.swift       # OCR scan history management
```

### Concurrency Model

- **@MainActor** - `ScreenCaptureManager` runs exclusively on main thread to prevent race conditions
- **DispatchQueue** - Background OCR processing with main thread callbacks
- **Task { @MainActor in }** - Safe async operations on main actor

### Security

- **Keychain Storage** - Gemini API key stored securely in macOS Keychain
- **Permission Checks** - Accessibility and Screen Recording permissions verified before use
- **No Network Logging** - API keys never logged or exposed

---

## Installation & Building

### Requirements

- macOS 11.0 (Big Sur) or later
- Xcode Command Line Tools
- Swift 5.5+

### Building from Source

1. **Clone the repository:**
   ```bash
   git clone https://github.com/sassongal/JoyaFix.git
   cd JoyaFix
   ```

2. **Build the app:**
   ```bash
   chmod +x build.sh
   ./build.sh
   ```

3. **Run the app:**
   ```bash
   open build/JoyaFix.app
   ```

4. **Install to Applications (optional):**
   ```bash
   cp -r build/JoyaFix.app /Applications/
   ```

### First Run Setup

1. **Grant Permissions:**
   - **Accessibility** - Required for keyboard simulation (Cmd+C, Cmd+V, Delete)
   - **Screen Recording** - Required for OCR screen capture
   
   The app will guide you through the permission setup on first launch.

2. **Configure API Keys (required for AI features):**
   - Right-click menubar icon → Settings → API Configuration
   - Choose AI Provider: Gemini or OpenRouter
   - Enter your API key
   - For OpenRouter: Select a model or enter a custom model ID
   - Click "Test" to verify your API key works
   - Save settings

3. **Configure Other Settings (optional):**
   - Customize hotkeys, history limit, and other preferences
   - Add text snippets for quick expansion

---

## Usage Guide

### Text Conversion

1. **Select text** in any application
2. **Press `⌘⌥K`** (or your custom hotkey)
3. Text is automatically converted and pasted

**Tips:**
- Works with rich text (preserves formatting)
- Supports mixed Hebrew/English text
- Handles uppercase letters correctly

### OCR Screen Capture

1. **Press `⌘⌥X`** to start OCR
2. **Drag** to select screen region
3. **Press ENTER** to confirm or **ESC** to cancel
4. Extracted text is saved to OCR history and copied to clipboard

**Tips:**
- Works across multiple monitors
- Use cloud OCR for better accuracy (requires Gemini API key)
- Local OCR works offline

### Text Snippets

1. **Add Snippet:**
   - Right-click menubar icon → Settings → Snippets tab
   - Click "+" to add new snippet
   - Enter trigger (e.g., `!mail`) and content

2. **Use Snippet:**
   - Type the trigger anywhere
   - It automatically expands to the full content

**Tips:**
- Triggers are case-insensitive
- Must be unique
- Works globally in all apps

### Clipboard History

1. **Access History:**
   - Click menubar icon to open popover
   - Or use `⌘1-9` for quick access

2. **Paste Options:**
   - **Regular Click** - Paste with formatting
   - **Shift+Click** - Paste as plain text
   - **Option+Click** - Paste as plain text

3. **Pin Items:**
   - Right-click item → Pin
   - Pinned items stay at the top

---

## Troubleshooting

### Text Conversion Not Working

**Problem:** Hotkey pressed but nothing happens

**Solutions:**
1. **Check Accessibility Permissions:**
   - System Settings → Privacy & Security → Accessibility
   - Ensure JoyaFix is enabled ✓

2. **Verify Hotkey Registration:**
   - Run app from terminal: `./test.sh`
   - Look for: `✓ Conversion hotkey registered: ⌘⌥K`
   - If you see an error, the hotkey may be reserved by another app

3. **Try Different Hotkey:**
   - Settings → General → Click hotkey button
   - Record a new combination (must include modifier: Cmd, Option, Shift, or Control)

4. **Check Console Logs:**
   ```bash
   log stream --predicate 'process == "JoyaFix"' --level debug
   ```

### OCR Not Working

**Problem:** Screen capture fails or no text extracted

**Solutions:**
1. **Check Screen Recording Permission:**
   - System Settings → Privacy & Security → Screen Recording
   - Ensure JoyaFix is enabled ✓

2. **Verify Selection:**
   - Make sure selection rectangle is large enough (>10x10 pixels)
   - Press ENTER after selecting (don't just release mouse)

3. **Check OCR Method:**
   - Settings → General → OCR Settings
   - Try switching between Cloud OCR and Local OCR
   - For Cloud OCR, ensure Gemini API key is set

4. **Multi-Monitor Issues:**
   - OCR works across all monitors
   - Selection coordinates are automatically converted

### Snippets Not Expanding

**Problem:** Typing trigger doesn't expand

**Solutions:**
1. **Check Accessibility Permission:**
   - Required for snippet expansion
   - System Settings → Privacy & Security → Accessibility

2. **Verify Snippet Exists:**
   - Settings → Snippets tab
   - Ensure snippet is listed and trigger is correct

3. **Check Trigger Format:**
   - Triggers are case-insensitive
   - Must match exactly (including special characters)

4. **Restart InputMonitor:**
   - Quit and relaunch JoyaFix
   - InputMonitor starts automatically if permissions are granted

### Clipboard History Not Saving

**Problem:** History disappears after app restart

**Solutions:**
1. **Check UserDefaults:**
   - History is stored in UserDefaults
   - Ensure app has write permissions

2. **Clear and Rebuild:**
   ```bash
   rm -rf build/
   ./build.sh
   ```

3. **Check Console for Errors:**
   ```bash
   log stream --predicate 'process == "JoyaFix"'
   ```

### Menubar Icon Disappears

**Problem:** Icon missing from menubar

**Solutions:**
1. **Check App is Running:**
   - Open Activity Monitor
   - Search for "JoyaFix"
   - If not running, launch the app

2. **Restart App:**
   ```bash
   killall JoyaFix
   open build/JoyaFix.app
   ```

3. **Check Logo File:**
   - Ensure `FLATLOGO.png` exists in app bundle
   - Rebuild if necessary: `./build.sh`

### Hotkey Conflicts

**Problem:** Hotkey registration fails

**Solutions:**
1. **Check System Shortcuts:**
   - System Settings → Keyboard → Keyboard Shortcuts
   - Look for conflicting shortcuts

2. **Check Other Apps:**
   - Some apps register global hotkeys (Spotlight, Alfred, etc.)
   - Try a different combination

3. **Reserved Combinations:**
   - Avoid: `⌘Space`, `⌘Tab`, `⌘Q`, `⌘C`, `⌘V`
   - Always include a modifier (Cmd, Option, Shift, Control)

---

## Technical Details

### Hotkey System

JoyaFix uses Carbon Events API for global hotkey registration:

- **High Priority** - Hotkeys work even when app is in background
- **System-Wide** - Works in all applications
- **Immediate Binding** - Changes apply instantly (no restart required)
- **Save & Rebind** - Settings saved to UserDefaults, hotkeys rebound immediately

See `HOTKEY_SYSTEM.md` for detailed documentation.

### Memory Optimization

JoyaFix is optimized for minimal memory usage:

- **String Truncation** - Preview text limited to 200 characters
- **Strict Deduplication** - No duplicate clipboard items
- **Lazy RTF Loading** - Rich text data only loaded when needed
- **Smart Storage** - Full text stored separately for large content

See `OPTIMIZATION.md` for detailed documentation.

### Permission Requirements

| Permission | Purpose | Required For |
|------------|---------|--------------|
| **Accessibility** | Simulate keyboard events | Text conversion, snippets, keyboard cleaner |
| **Screen Recording** | Capture screen content | OCR feature |

### API Integration

JoyaFix supports two AI providers:

**1. Gemini (Google AI):**
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent`
- API Key: Stored securely in Keychain
- Get your free API key: [Google AI Studio](https://aistudio.google.com/app/apikey)
- Features: Text generation, Vision Lab (image description), OCR
- Free tier available

**2. OpenRouter:**
- Endpoint: `https://openrouter.ai/api/v1/chat/completions`
- API Key: Stored securely in Keychain
- Get your API key: [OpenRouter](https://openrouter.ai/keys)
- Features: Access to multiple AI models, Vision Lab support
- Supported Models:
  - **Free Models:**
    - `deepseek/deepseek-chat` - Fast and free chat model
    - `mistralai/mistral-7b-instruct` - Mistral 7B Instruct
    - `meta-llama/llama-3.3-70b-instruct` - Llama 3.3 70B
    - `google/gemini-1.5-flash` - Gemini 1.5 Flash (supports vision)
  - **Custom Models:** You can use any model supported by OpenRouter by entering the model ID manually

**Configuration:**
1. Open Settings → API Configuration
2. Select your preferred AI provider (Gemini or OpenRouter)
3. Enter your API key
4. For OpenRouter, select a model from the dropdown or enter a custom model ID
5. Click "Test" to verify your API key
6. Save settings

**Troubleshooting API Issues:**
- **Invalid API Key:** Check that your API key is correct and has the necessary permissions
- **Rate Limit Exceeded:** Wait a few moments and try again, or upgrade your API plan
- **Network Error:** Check your internet connection
- **Model Not Found:** For OpenRouter, ensure the model ID is correct (format: `provider/model-name`)

---

## Development

### Project Structure

```
JoyaFix/
├── *.swift              # Swift source files
├── Info.plist           # App configuration
├── FLATLOGO.png         # App logo
├── success.wav          # Success sound effect
├── build.sh             # Build script
├── README.md            # This file
├── DEBUG.md             # Debugging guide
├── OPTIMIZATION.md      # Memory optimization details
├── HOTKEY_SYSTEM.md     # Hotkey system documentation
└── build/               # Build output directory
```

### Building

```bash
# Standard build
./build.sh

# Run tests (if available)
./test.sh

# Clean build
rm -rf build/
./build.sh
```

### Debugging

1. **Run from Terminal:**
   ```bash
   ./test.sh
   ```

2. **View Console Logs:**
   ```bash
   log stream --predicate 'process == "JoyaFix"' --level debug
   ```

3. **Check Activity Monitor:**
   - Monitor memory usage
   - Check CPU usage
   - Verify app is running

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

---

## Credits

- **Created by:** Gal Sasson
- **Powered by:** JoyaTech
- **Version:** 1.0.0
- **Copyright:** © 2026 JoyaTech. All Rights Reserved.

---

## License

This project is open source and available for use under the MIT License.

---

**Enjoying JoyaFix? Give it a ⭐ on GitHub!**
