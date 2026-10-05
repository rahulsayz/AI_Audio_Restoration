# Sangeet AI private Beta Release Runbook

This document serves as Sangeet AI's canonical runbook for building, packaging, notarizing, and distributing private invite-only beta releases. Execute each step sequentially, verifying all outputs before proceeding.

---

## Phase 1: Git Tagging (`v1.0.0-beta1`)
Before building, establish a stable git release tag in the repository.

1.  **Check Status**:
    *   Verify the working directory is clean and fully merged to the target branch:
        ```bash
        git status
        ```
2.  **Tag the Release**:
    *   Apply a signed git tag for the beta version:
        ```bash
        git tag -s v1.0.0-beta1 -m "Sangeet AI private Beta 1 Release"
        ```
3.  **Push Tag to Remote**:
    *   Push the tagged commit to the remote origin:
        ```bash
        git push origin v1.0.0-beta1
        ```

---

## Phase 2: Build the Final Release DMG
We package Sangeet and its embedded localized Python inference daemon into a hardened, codesigned, and notarized DMG archive using Sangeet's orchestrator script.

1.  **Environment Credentials**:
    *   Ensure your Apple Developer ID certificates are active in Keychain, and export your Notarization credentials to your environment variables:
        ```bash
        export APPLE_ID="your-developer-apple-id@email.com"
        export APPLE_TEAM_ID="ABC123XYZ"
        export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
        ```
2.  **Execute Release Script**:
    *   Run Sangeet's release orchestrator, providing your codesigning identity and version:
        ```bash
        ./scripts/release.sh "Developer ID Application: Rahul Chaturvedi (ABC123XYZ)" "1.0.0-beta1"
        ```
3.  **Verify Outputs**:
    *   Confirm the build completes successfully with **Exit Code: 0**.
    *   Locate the signed and notarized installer archive at:
        `dist/SangeetAI-1.0.0-beta1.dmg`

---

## Phase 3: Upload Release to Cloudflare R2
Beta releases are hosted in our secure, private Cloudflare R2 bucket.

1.  **S3-Compatible CLI Configuration**:
    *   Verify `aws-cli` or `rclone` is configured with your Cloudflare R2 endpoint:
        ```bash
        # R2 Endpoint format: https://<account_id>.r2.cloudflarestorage.com
        aws configure set plugins.endpoint awscli_plugin_endpoint
        ```
2.  **Upload DMG to R2 Bucket**:
    *   Upload the notarized file to the private beta bucket:
        ```bash
        aws s3 cp dist/SangeetAI-1.0.0-beta1.dmg s3://sangeet-builds-beta/SangeetAI-1.0.0-Beta.dmg --endpoint-url https://$CLOUDFLARE_ACCOUNT_ID.r2.cloudflarestorage.com
        ```
3.  **Verify Object**:
    *   Check R2 storage to confirm the file is uploaded, metadata matches, and access permissions are set to strictly **Private** (no public access).

---

## Phase 4: Generate Sparkle Appcast Entry
We must append our new version details and DSA/EdDSA cryptographic signatures into Sparkle's update feed.

1.  **Generate EdDSA Signature**:
    *   Use Sparkle's bundled keys generator to sign the new DMG archive:
        ```bash
        # Locates private key and generates the signature string
        ./bin/sign_update dist/SangeetAI-1.0.0-beta1.dmg
        ```
    *   *Note: Save the returned signature hash (e.g., `ed25519="xxxx..."`).*
2.  **Edit `appcast.xml`**:
    *   Locate your Sparkle appcast feed file. Add the new beta enclosure tag:
        ```xml
        <item>
            <title>Version 1.0.0-Beta 1</title>
            <sparkle:releaseNotesLink>https://updates.sangeet.app/beta/release-notes-1.0.0-beta1.html</sparkle:releaseNotesLink>
            <pubDate>Sun, 17 May 2026 20:58:00 +0530</pubDate>
            <enclosure 
                url="https://updates.sangeet.app/beta/download/SangeetAI-1.0.0-Beta.dmg" 
                sparkle:version="1.0.0-beta1" 
                sparkle:shortVersionString="1.0.0" 
                length="128450122" 
                type="application/octet-stream" 
                sparkle:edSignature="[PASTE_GENERATED_EDSignature_HERE]" />
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
        </item>
        ```

---

## Phase 5: Push Appcast to Production Beta URL
The Sparkle feed is served via Cloudflare Pages under the private beta updates domain.

1.  **Publish Updates**:
    *   Deploy the updated `appcast.xml` file to your Cloudflare Pages target directory:
        ```bash
        wrangler pages deploy docs/updates --project-name sangeet-updates-beta
        ```
2.  **Verify Endpoint Feed**:
    *   Perform a validation curl call and verify the server outputs the new enclosure details successfully:
        ```bash
        curl -s https://updates.sangeet.app/beta/appcast.xml | grep "1.0.0-beta1"
        ```

---

## Phase 6: Invite the First 5 Beta Users
We initialize our private rollout with our first 5 core Indian music archivist contacts.

1.  **Generate Cryptographic Private URLs**:
    *   For each email address, run Sangeet's secure invitation generator. This generates a 7-day cryptographically signed download link and registers the invite in our tracking database:
        ```bash
        ./scripts/invite-beta-user.py archivist1@archive.org
        ./scripts/invite-beta-user.py collector2@gmail.com
        ./scripts/invite-beta-user.py scholar3@classical.in
        ./scripts/invite-beta-user.py master4@studio.in
        ./scripts/invite-beta-user.py restorer5@audiocollect.org
        ```
2.  **Send Welcome Emails**:
    *   Copy the welcome email template from [docs/playbooks/beta-welcome-email.md](file:///Users/rahulchaturvedi/AI_Audio_Restoration/docs/playbooks/beta-welcome-email.md).
    *   Populate the personal signed R2 invite URL at the `[YOUR_PERSONAL_SIGNED_URL]` placeholder.
    *   Dispatch via personal email (e.g., from `rahul@sangeet.app`).

---

## Phase 7: Post-Launch Telemetry Audit (24 Hours)
Wait 24 hours to monitor initial system integrity and gather diagnostic feedback.

1.  **Monitor Crash Diagnostics**:
    *   Check your `beta@sangeet.app` email inbox and telemetry databases.
    *   Confirm **zero** severe crashes have been logged, and any submitted feedback forms contain healthy, readable diagnostics YAML.
2.  **Inspect Restoration Pipeline Timings**:
    *   Review post-hog / local event telemetry averages.
    *   Verify the average processing duration on M-series architectures continues to meet Sangeet's realtime DSP targets.

---

## Phase 8: Rolling Wave Expansion
If the initial 24-hour audit phase yields clean performance results, proceed with rolling wave invitations to the remaining 25 testers:

1.  **Wave 2 (Next 10 Users)**:
    *   Generate links and dispatch welcome emails to testers 6 through 15.
    *   Audit incoming feedback submissions for 12 hours.
2.  **Wave 3 (Final 15 Users)**:
    *   Generate links and dispatch welcome emails to testers 16 through 30.
    *   Finalize Sangeet private beta rollout phase.
