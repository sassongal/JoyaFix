# Swift Package Manager Migration Guide

This document outlines the migration of JoyaFix from raw `swiftc` builds to Swift Package Manager (SPM) with professional tooling.

## ✅ Completed Setup

### 1. Package.swift
- Created `Package.swift` with SPM configuration
- Added dependencies: Sparkle (2.5.0+) and Pulse (4.0.0+)
- Configured executable target with proper frameworks (Cocoa, Carbon, ApplicationServices)
- Set up test target `JoyaFixTests`

### 2. Project Structure Migration
- Created `migrate_to_spm.sh` script to restructure the project
- Script moves all Swift files to `Sources/JoyaFix/`
- Script moves resources to `Sources/JoyaFix/Resources/`

### 3. Tooling Integration

#### SwiftLint
- Created `.swiftlint.yml` with strict but reasonable rules
- Disabled `trailing_whitespace` and `line_length` to avoid noise during migration

#### XCTest
- Created `Tests/JoyaFixTests/JoyaFixTests.swift`
- Added basic test cases for `TextConverter` (verifies "shalom" -> "שלום" logic)

#### Pulse
- Added Pulse import to `JoyaFixApp.swift`
- Added initialization comment (Pulse auto-intercepts URLSession when imported)

#### Sparkle
- Added Sparkle import to `UpdateManager.swift`
- Initialized `SPUStandardUpdaterController` (prepared for full integration)
- Kept existing custom update checking as fallback

### 4. Build Script
- Updated `build.sh` to use `swift build -c release`
- Added `swift test` step before building
- Updated resource copying to work with SPM structure
- Maintains backward compatibility with root-level resources

## 🚀 Migration Steps

### Step 1: Run the Migration Script

```bash
cd /Users/galsasson/Desktop/JoyaFix
./migrate_to_spm.sh
```

This will:
- Create `Sources/JoyaFix/` directory
- Move all `.swift` files to `Sources/JoyaFix/`
- Move resources to `Sources/JoyaFix/Resources/`
- Create `Tests/JoyaFixTests/` directory

### Step 2: Verify Package Resolution

```bash
swift package resolve
```

This will download Sparkle and Pulse dependencies.

### Step 3: Run Tests

```bash
swift test
```

Verify that the TextConverter tests pass.

### Step 4: Build the App

```bash
./build.sh
```

This will:
1. Run tests
2. Build with `swift build -c release`
3. Create the app bundle in `build/JoyaFix.app/`
4. Copy all resources to the bundle

### Step 5: Test the App

```bash
open build/JoyaFix.app
```

Verify that the app launches and works as before.

## 📝 Next Steps (Optional)

### Full Sparkle Integration
To complete Sparkle integration:
1. Add to `Info.plist`:
   - `SUFeedURL`: URL to your appcast.xml
   - `SUPublicEDSAKey`: Your public key for signing
2. Replace custom update checking in `UpdateManager.swift` with Sparkle's UI
3. Add "Check for Updates..." menu item connected to `updaterController.checkForUpdates()`

### Full Pulse Integration
To add Pulse UI for viewing network logs:
1. Add `PulseUI` product to Package.swift dependencies
2. Import `PulseUI` in your settings view
3. Add `PulseView()` to display network logs

### SwiftLint Integration
To run SwiftLint:
```bash
# Install SwiftLint if not already installed
brew install swiftlint

# Run SwiftLint
swiftlint lint
```

## ⚠️ Important Notes

1. **Resources**: The build script checks both `Sources/JoyaFix/Resources/` and root directory for backward compatibility
2. **Info.plist**: Make sure `Info.plist` is copied correctly - the build script handles this
3. **Dependencies**: Sparkle and Pulse are automatically resolved by SPM
4. **Testing**: Tests run automatically before each build

## 🔧 Troubleshooting

### Build Fails with "No such module"
- Run `swift package resolve` to download dependencies
- Ensure you're in the project root directory

### Resources Not Found at Runtime
- Verify resources are in `Sources/JoyaFix/Resources/`
- Check that `build.sh` copied them to the app bundle
- Ensure `Package.swift` has `.process("Resources")` in resources array

### Tests Fail
- Ensure all source files are in `Sources/JoyaFix/`
- Check that test file imports `@testable import JoyaFix`

## 📚 References

- [Swift Package Manager Documentation](https://swift.org/package-manager/)
- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Pulse Documentation](https://github.com/kean/Pulse)
- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)

