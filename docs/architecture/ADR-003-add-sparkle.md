# ADR-003: Integrate Sparkle 2.x for Automated App Updates

Date: 2026-05-17
Status: Proposed

## Context
Sangeet AI is distributed as a standalone macOS desktop application bundle outside the Mac App Store to support direct distribution, dynamic daemon loading, and custom installers.
To deliver a premium product experience, we need a reliable, native mechanism to notify users of updates, show visual release notes, and install updates.
The update system must:
1. Support secure update signing using modern EdDSA (Ed25519) cryptography to prevent tampering or man-in-the-middle attacks.
2. Provide granular user control over update checking frequency (daily, weekly, monthly) and automatic downloads.
3. Be friendly to metered or slow internet connections (common in India), meaning it must default to *not* automatically downloading updates without the user's explicit consent, while allowing manual update checks.
4. Integrate seamlessly with the existing SwiftUI application lifecycle and look native and premium.
5. Use a static-file hosting model (such as Cloudflare Pages) for high availability, low maintenance, and fast feed downloads.

## Decision
We will integrate **Sparkle 2.x** (specifically `2.6.x` or newer) via the Swift Package Manager dependency already declared in `packages/audio-engine/Package.swift`. 
We will:
1. Configure `project.pbxproj` build settings with standard Info.plist keys:
   - `INFOPLIST_KEY_SUFeedURL = "https://updates.sangeet.app/appcast.xml";`
   - `INFOPLIST_KEY_SUPublicEDKey = "<our public key>";`
2. Create an `UpdaterViewModel` in Swift to wrap the `SPUStandardUpdaterController` and expose update actions to our SwiftUI menus and views.
3. Expose granular controls in the Preferences panel (`SettingsView.swift`) under a new "Updates" section in `GeneralSettingsView`:
   - "Check for updates automatically" (`SUEnableAutomaticChecks`)
   - "Automatically download updates" (`SUAutomaticallyUpdate` - defaulted to `NO` to preserve metered bandwidth)
   - "Check Interval" (`SUScheduledCheckInterval` - defaulted to weekly / 604,800 seconds)
4. Add a native "Check for Updates..." button under the main application menu using SwiftUI `.commands` and in the "About" tab of settings.
5. Generate an EdDSA (Ed25519) keypair using Sparkle's `generate_keys` tool, storing the private key securely in the developer's macOS Keychain (never committed to git) and document this workflow in `docs/playbooks/release-signing.md`.
6. Set up a static file layout in `/updates` (intended for hosting on Cloudflare Pages) featuring `appcast.xml`, a basic `index.html`, and a template for HTML release notes.

## Consequences
- **Pros**:
  - Sparkle is the de facto standard for macOS application updates, highly mature and widely trusted.
  - Zero-maintenance server footprint: updates are served via static files (XML, HTML, and ZIP/DMG binaries) hosted on a CDN (Cloudflare Pages/R2).
  - High security: Ed25519 signing ensures updates cannot be spoofed.
  - Native feel: users see standard macOS update alerts with rich HTML release notes.
- **Cons**:
  - Adds a dynamic framework bundle to the final signed macOS application bundle.
  - Requires developers to maintain their private key in their macOS Keychain (or secure backups) to sign future updates.

## Alternatives considered

### 1. Custom Update Checker
- **Why rejected**: A custom checker would require writing a network polling engine, parsing a custom JSON manifest, displaying a custom download UI, and handling mounting DMG files or replacing app bundles in Swift. This is highly prone to security vulnerabilities (privilege escalation, lack of signing checks) and has massive development overhead compared to using Sparkle.

### 2. Mac App Store (MAS) Updates
- **Why rejected**: MAS distribution restricts our app with strict Sandboxing. Sandboxing prevents launching our standalone Python ML inference daemon locally on-demand via launch agents, and would require complex XPC boundaries or hosting the inference pipeline in the cloud, which violates our absolute privacy requirement (no audio leaves the device).
