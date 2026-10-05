# Sangeet AI Beta Release Pre-Flight Checklist

This checklist must be executed and fully verified before compiling, signing, and distributing any release build to our 30 private beta testers. **Zero exceptions.** Every checkbox must be marked `[x]` on at least three physical Macs representing different Apple Silicon generations.

---

## 1. Multi-Device Hardware Validation
Verify the compiled application launches and restores audio on a minimum of three distinct Mac configurations:

- [ ] **M1 Generation (e.g., M1 MacBook Air / M1 Max MacBook Pro)**
    *   CPU: Apple Silicon M1 series
    *   OS Version: macOS 13 Ventura (Minimum Deployment Target) or macOS 14/15
    *   Verify: Core ML/PyTorch loading does not crash; memory footprint remains under 4 GB.
- [ ] **M2 Generation (e.g., M2 MacBook Pro baseline / M2 Mac mini)**
    *   CPU: Apple Silicon M2 series
    *   OS Version: macOS 14 Sonoma
    *   Verify: The default restoration chain processes a 30-second stereo segment in under 15 seconds (at least 2x realtime).
- [ ] **M3 / M4 Generation (e.g., M3 Pro MacBook Pro / M4 iMac)**
    *   CPU: Apple Silicon M3/M4 series
    *   OS Version: macOS 15 Sequoia (Current Latest)
    *   Verify: Accelerated audio engine DSP does not trigger layout clipping or concurrency warnings.

---

## 2. Gatekeeper and Signing Integrity
Ensure the final `.dmg` container bypasses Apple's security warnings cleanly:

- [ ] **Code Signing Verification**:
    *   Run `codesign --verify --verbose=4 SangeetAI.app` inside the build output.
    *   Ensure the embedded Python daemon folder (`SangeetAI.app/Contents/Resources/sangeet-inference`) is recursively signed with the Developer ID Application certificate.
- [ ] **Notarization Ticket**:
    *   Submit build using `xcrun notarytool submit` and verify status is `Accepted`.
    *   Staple the notarization ticket to the DMG: `xcrun stapler staple SangeetAI.dmg`.
- [ ] **Clean Download Trial**:
    *   Download the stapled DMG from Cloudflare R2 onto a clean test machine.
    *   Double-click to mount and drag to `/Applications`.
    *   Double-click `/Applications/SangeetAI.app`. Verify it launches **without** "unidentified developer" warnings or quarantine block sheets.

---

## 3. First-Launch Onboarding Integrity
Validate that first-time users experience a flawless onboarding sequence:

- [ ] **Reset Local States**:
    *   Before running, execute in Terminal:
        ```bash
        defaults delete ai.sangeet.SangeetAI.beta
        rm -rf ~/Library/Application\ Support/SangeetAI/
        ```
- [ ] **Onboarding Trigger**:
    *   Launch Sangeet AI. Verify that the 5-screen `OnboardingView` sheet presents immediately.
    *   Verify the app's main workspace is blurred and fully inactive behind the sheet.
- [ ] **Flow Navigation**:
    *   Progression works cleanly using "Next" and "Back" buttons.
    *   The horizontal flowchart on Screen 2 is cleanly aligned and legible.
- [ ] **State Persistence**:
    *   Complete the onboarding flow by clicking "Start Restoring".
    *   Quit the app and re-launch. Verify the onboarding sheet is **not** displayed, and Sangeet opens directly into the main restoration workspace.

---

## 4. Onboarding Trial Audio Restoration
Verify that the offline sample restoration is fully functional:

- [ ] **File Loading**:
    *   Select each of the three built-in tracks on Screen 3:
        1.  **Noisy Playback Recording** (`noisy_playback.wav`)
        2.  **Scratchy Classical Recording** (`scratchy_classical.wav`)
        3.  **Muffled Tape Recording** (`muffled_tape.wav`)
    *   Confirm they resolve to their embedded bundle resources without returning file errors.
- [ ] **Inline Progress Monitoring**:
    *   Click "Restore Selected Track".
    *   Verify the orange progress bar fills up smoothly, and current stages (e.g., `DeepFilterNet Denoising...`) reflect actual ML daemon progress.
- [ ] **Mini A/B Player Playback**:
    *   Verify audio playback loop initializes successfully upon restoration completion.
    *   Toggle **Original vs Restored** switches. Confirm audio exchanges cleanly without clicks, pops, or synchronization drift.
    *   Toggle **Volume Matching**. Confirm the original track gains are normalized to match the restored track integrated LUFS level.

---

## 5. Beta Feedback Widget & Resend API Integration
Confirm users can submit diagnostic logs and audio attachments directly from their workspace:

- [ ] **Feedback Trigger**:
    *   Load any custom audio file into Sangeet AI.
    *   Click the **Feedback** button in the bottom left corner of the sidebar. Verify the feedback sheet presents cleanly.
- [ ] **Diagnostic Checks**:
    *   Check "Attach last restoration audio + analysis YAML".
    *   Enter a description (e.g., "Beta Pre-Flight Connection Test") and click **Send**.
- [ ] **Offline Queue Recovery**:
    *   Disconnect Wi-Fi (offline mode). Submit another feedback form.
    *   Verify that `FeedbackQueueManager` writes a `.json` diagnostic package under `~/Library/Application Support/SangeetAI/feedback_queue/`.
    *   Reconnect Wi-Fi. Wait for the background thread to run or re-launch the app. Verify the queue is successfully flushed and the local `.json` is deleted.
- [ ] **Email Inbox Delivery**:
    *   Open the `beta@sangeet.app` inbox.
    *   Confirm the submission email was delivered containing:
        *   Correct sender details (the tester's email address)
        *   Structured diagnostic table (macOS version, hardware model, total RAM)
        *   The restored WAV file (attached, under 15MB limit)
        *   The analysis metadata YAML file.

---

## 6. Telemetry Consent Opt-Out Verification
Verify that Sangeet respects privacy boundaries:

- [ ] **Opt-Out Check**:
    *   On Screen 4 of the onboarding tour, select **Skip Diagnostics**.
    *   Open `~/Library/Preferences/ai.sangeet.SangeetAI.beta.plist` or inspect UserDefaults.
    *   Verify `"SAITelemetryEnabled"` is written as `false`.
- [ ] **Zero Network Contacts**:
    *   With diagnostics disabled, run a full restoration.
    *   Inspect local console outputs. Confirm **no** telemetry POST requests are queued or dispatched to our PostHog/telemetry endpoint.

---

## 7. Sparkle Auto-Update Feed
Ensure beta users get immediate updates when we patch builds:

- [ ] **Feed Resolution**:
    *   Open `https://updates.sangeet.app/beta/appcast.xml` in a browser.
    *   Confirm the XML schema parses cleanly, matches Sparkle's format, and points to the correct beta DMG download URL.
- [ ] **In-App Check**:
    *   Click **Sangeet AI** $\rightarrow$ **Check for Updates...** in the menu bar.
    *   Confirm the update check completes cleanly. If the local build version is older than the appcast, verify the Sparkle update sheet presents with our release notes.

---

## 8. Crash Reporter Integration
Confirm Sangeet captures critical crashes locally and prompts the user on subsequent launch:

- [ ] **Deliberate Crash Test**:
    *   Click **Help** $\rightarrow$ **Trigger Diagnostic Crash** (beta menu item).
    *   Confirm Sangeet terminates instantly.
- [ ] **Crash Dump Collection**:
    *   Confirm a standard stack dump is written under `~/Library/Application Support/SangeetAI/crashes/`.
- [ ] **Recovery Prompt**:
    *   Re-launch the app.
    *   Confirm a crash recovery alert is displayed: *"Sangeet quit unexpectedly on your last session. Would you like to share this crash diagnostic to help us fix the issue?"*
    *   Click **Share**. Verify the stack trace JSON is dispatched to the feedback API.

---

## 9. About Screen Metadata
Verify all versioning, licensing, and beta indicators are up to date:

- [ ] **Version and Build**:
    *   Click **Sangeet AI** $\rightarrow$ **About Sangeet AI**.
    *   Verify the dialog reads exactly: `Version 0.10.0 (Beta 1)`.
    *   Verify the titlebar shows `[BETA]` next to the project name.
- [ ] **License Hygiene**:
    *   Verify the Third-Party Licenses scroll-view lists our correct dependencies: `Sparkle`, `grpc-swift`, `DeepFilterNet`, and `soundfile` along with their full MIT/Apache licenses.

---

## 10. Evaluation Quality Baseline
Lock in the restoration quality metrics before shipping:

- [ ] **Benchmark Check**:
    *   Run the complete evaluation suite on our 100-song corpus:
        ```bash
        make eval
        ```
    *   Confirm that the overall integrated SI-SDR improvement is at least **+8.4 dB** on historical material.
    *   Confirm **zero** severe transient anomalies in our protected Hindustani vocal reference list.
    *   Save `eval/reports/v0.10.x_baseline.json` as the official release quality anchor.
