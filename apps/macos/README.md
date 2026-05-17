# Sangeet AI — macOS SwiftUI Application (`apps/macos/`)

This directory houses the native SwiftUI macOS front-end for **Sangeet AI**.

---

## 1. Project Structure

- `Sources/SangeetAI/`
  - [SangeetAIApp.swift](file:///Users/rahulchaturvedi/AI_Audio_Restoration/apps/macos/Sources/SangeetAI/SangeetAIApp.swift): Main application entry point enforcing the 800x600 fixed content boundaries.
  - [RestorationView.swift](file:///Users/rahulchaturvedi/AI_Audio_Restoration/apps/macos/Sources/SangeetAI/RestorationView.swift): Visual front-end, implementing premium space-dark glassmorphism aesthetics, saffron-gold and neon-teal heritage/tech theme, interactive drag-and-drop file imports, and capitalized progress status overlays.
  - [RestorationViewModel.swift](file:///Users/rahulchaturvedi/AI_Audio_Restoration/apps/macos/Sources/SangeetAI/RestorationViewModel.swift): Reactive View Model managing state, AVFoundation local metadata checks, streaming gRPC client tracking, and environment bindings.
  - [VisualEffects.swift](file:///Users/rahulchaturvedi/AI_Audio_Restoration/apps/macos/Sources/SangeetAI/VisualEffects.swift): Shared styling utilities, custom glass modifiers, glow transitions, and animated soundwave backgrounds.
- `Tests/SangeetAITests/`
  - [SangeetAITests.swift](file:///Users/rahulchaturvedi/AI_Audio_Restoration/apps/macos/Tests/SangeetAITests/SangeetAITests.swift): Frontend unit test validations for reactive state and metadata inputs.

---

## 2. Development Setup & Linking Packages

The Sangeet AI macOS application depends directly on the local **AudioEngine** Swift Package located at `../../packages/audio-engine`.

### Linking the Package in Xcode
1. Open `SangeetAI.xcodeproj` (or create a new macOS SwiftUI project of type App named `SangeetAI`).
2. Add the `audio-engine` package to the project:
   - Drag the folder `packages/audio-engine` from Finder into the Xcode project navigator sidebar, OR
   - Go to **File** > **Add Packages...** > click **Add Local...** > select the folder `packages/audio-engine`.
3. Select the `SangeetAI` target, navigate to **General** > **Frameworks, Libraries, and Embedded Content**, and click `+` to add the `AudioEngine` library target.

---

## 3. Environment Configuration (`SANGEET_DAEMON_PATH`)

To facilitate background daemon execution during development, the application requires the `SANGEET_DAEMON_PATH` environment variable pointing to your locally compiled or run python daemon folder/binary.

### Hardcoding the Daemon Path in Xcode Schemes
To configure Xcode to automatically launch the local development daemon:
1. In the top bar of Xcode, click the active scheme `SangeetAI` and choose **Edit Scheme...** (or press `Cmd + <`).
2. Select **Run** from the left-hand column, and choose the **Arguments** tab.
3. In the **Environment Variables** list, click `+` to add a new environment variable:
   - **Name**: `SANGEET_DAEMON_PATH`
   - **Value**: `/Users/rahulchaturvedi/AI_Audio_Restoration/services/inference/dist/sangeet-inference` (or the absolute path to your locally built daemon executable/development runner).
4. Check the box to enable it.
5. Click **Close**.

---

## 4. Building the Application

To compile and verify the application via command-line:
```bash
xcodebuild -scheme SangeetAI build
```
To run unit tests:
```bash
xcodebuild -scheme SangeetAI test
```
