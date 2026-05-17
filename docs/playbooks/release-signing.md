# Release Signing and Notarization Playbook — Sangeet AI

This playbook guides developers through setting up, signing, notarizing, packaging, and verifying a production release DMG for Sangeet AI.

---

## 1. Environment Setup (Credentials)

Apple's modern `notarytool` requires Developer credentials to submit signed app bundles or DMG files for notarization. In our orchestration scripts, these are read directly from system environment variables:

```bash
export APPLE_ID="your-developer-email@domain.com"
export APPLE_TEAM_ID="10_CHARACTER_TEAM_ID"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" # App-specific password generated via appleid.apple.com
```

> [!WARNING]
> Do NOT use your master Apple ID password for `APPLE_APP_PASSWORD`. You must generate a dedicated, 16-character app-specific password specifically for Sangeet AI releases on your Apple Developer account portal.

---

## 2. Security Entitlements & Hardened Runtime

Production macOS applications require **Hardened Runtime** enabled and the **App Sandbox** active. However, loading dynamic libraries from a frozen Python and PyTorch package introduces several unique restrictions that we handle in [SangeetAI.entitlements](file:///Users/rahulchaturvedi/AI_Audio_Restoration/apps/macos/Sources/SangeetAI/SangeetAI.entitlements):

### 2.1 Privileges Allowed
* `com.apple.security.app-sandbox` = `true` — Mandated for secure, modern macOS app distribution.
* `com.apple.security.network.client` = `true` — Allows the app/daemon to communicate outward to download required ML weights on first use.
* `com.apple.security.files.user-selected.read-write` = `true` — Allows users to drop audio files to import and select output locations to export restored files.

### 2.2 Hardened Runtime Exemptions
* `com.apple.security.cs.allow-jit` = `true` — Allows dynamic Python/PyTorch compilation.
* `com.apple.security.cs.allow-unsigned-executable-memory` = `true` — Essential for Python's `ctypes` allocations.
* `com.apple.security.cs.disable-library-validation` = `true` — Allows the process to load third-party dynamic modules (`.so` and `.dylib` files compiled in PyInstaller) that do not share the host's Team ID signature.

---

## 3. Strict Inside-Out signing order

Gatekeeper enforces that nested contents must be signed *before* outer contents. If you modify or sign an inner binary after signing its parent bundle, the parent's directory hashes break, causing the app to fail Gatekeeper validation.

Our [codesign.sh](file:///Users/rahulchaturvedi/AI_Audio_Restoration/scripts/codesign.sh) script enforces this order:
1. **Nested Libraries:** Signs all `.so` and `.dylib` files inside the PyInstaller `_internal` dependency directory.
2. **Helper Executables:** Signs helper binaries (e.g. `torch_shm_manager`, `protoc`).
3. **Daemon Binary:** Signs the main `sangeet-inference` executable inside `Contents/Resources/sangeet-inference`.
4. **App Bundle:** Signs the outer `SangeetAI.app` bundle while attaching the `SangeetAI.entitlements` configuration plist.

---

## 4. How to Orchestrate a Release

A single `make` target triggers the entire release pipeline (building, signing inside-out, notarizing the app zip, stapling, DMG creation, DMG signing, DMG notarizing, and DMG stapling):

### 4.1 Local Development Dry-Run (Ad-hoc)
To verify the build, packaging, and DMG creations without using a paid Apple Developer certificate, run:
```bash
make release VERSION=0.10.0-beta1
```
This defaults `SIGNING_IDENTITY` to `-` (ad-hoc), skips credential-based notarizations, and outputs a signed, valid local DMG at `dist/SangeetAI-0.10.0-beta1.dmg`.

### 4.2 Production Notarized Release
Configure your environment variables and invoke:
```bash
export APPLE_ID="developer@company.com"
export APPLE_TEAM_ID="ABC123XYZ9"
export APPLE_APP_PASSWORD="abcd-efgh-ijkl-mnop"

make release VERSION=0.10.0-beta1 SIGNING_IDENTITY="Developer ID Application: Your Company (ABC123XYZ9)"
```
This outputs a fully signed, notarized, and double-stapled DMG at `dist/SangeetAI-0.10.0-beta1.dmg` ready for immediate public distribution!

---

## 5. Verification Command Reference

Validate your built artifacts using Apple's standard command line utilities:

### 5.1 Entitlements & Signature Audit
Verify that the outer app bundle carries the correct codesign identifiers and entitlements:
```bash
codesign -d --entitlements - build/DerivedData/Build/Products/Release/SangeetAI.app
```

### 5.2 Deep Bundle Verification
Audit the entire app package structure to ensure no nesting or signature violations exist:
```bash
codesign --verify --verbose --deep build/DerivedData/Build/Products/Release/SangeetAI.app
```

### 5.3 Gatekeeper Assessment
Confirm if Gatekeeper approves the application bundle for launch:
```bash
spctl --assess --type execute --verbose build/DerivedData/Build/Products/Release/SangeetAI.app
```

Confirm if the DMG itself is recognized and approved by Gatekeeper:
```bash
spctl --assess --type open --context context:primary-signature --verbose dist/SangeetAI-0.10.0-beta1.dmg
```

### 5.4 Notarization Logs
In the rare event of a notarization rejection, query Apple's validation log:
```bash
xcrun notarytool log <submission-uuid> --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
```
