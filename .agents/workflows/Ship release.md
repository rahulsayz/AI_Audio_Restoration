---
trigger: always_on
---

# Workflow: Ship Release

Triggered by: `/ship-release <version>`

End-to-end release workflow. Do not skip steps. Each gate exists to catch a class of bug that has bitten us before (or that we expect to bite us).

## Pre-flight

Ask the user:

1. Version number (semver, e.g., `1.2.0`)
2. Is this a beta or public release?
3. Any known issues to call out in release notes?

Confirm the working directory is clean and on `main`. Refuse if dirty or on a feature branch.

## Step 1 — Verify all tests pass

```bash
# Swift
xcodebuild test -scheme SangeetAI -destination 'platform=macOS'

# Python
cd services/inference && pytest

# Contract tests
make contract-tests

# Linters
make lint
```

Any failure aborts the release.

## Step 2 — Run /benchmark-pipeline

Run the benchmark workflow against the previous release tag.

Both performance and quality must be flat or improved. Any regression aborts the release.

## Step 3 — Listening panel sign-off

For non-patch releases (minor and major):

- Send the listening panel an A/B/X test of 20 random segments from the eval corpus.
- Require at least 2 of 3 panelists to sign off.
- Document feedback in `eval/listening-panel/<version>.md`.

Patch releases (`1.x.Y` where only Y changes) skip the panel unless the patch touches the restoration chain.

## Step 4 — License audit

Run:

```bash
make licenses
```

This regenerates the "About" screen license list from current lockfiles. Verify:

- No new dependencies have appeared without an ADR
- No accepted licenses have changed to rejected categories (rare but happens)
- All model weights still match the pinned SHA-256

Any discrepancy aborts the release.

## Step 5 — Update CHANGELOG and release notes

Update `CHANGELOG.md` with the new version section. Follow the format used in previous entries:

```markdown
## [1.2.0] — 2026-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...

### Removed
- ...
```

Write user-facing release notes in `docs/releases/<version>.md`. These appear in the Sparkle update dialog. Follow `.agents/rules/09-writing-and-comms.md` — direct, concrete, no marketing fluff.

## Step 6 — Tag and build

```bash
git tag -a v<version> -m "Sangeet AI <version>"
git push origin v<version>

make release VERSION=<version>
```

The release build:

- Builds Swift app in Release configuration
- Builds Python daemon via PyInstaller, signed
- Bundles daemon into app's Resources/
- Signs the full app bundle with Developer ID Application certificate
- Notarizes via `notarytool` (waits for completion)
- Staples the notarization ticket
- Produces `dist/SangeetAI-<version>.dmg`

Step 6 takes 15–30 minutes. Wait for it.

## Step 7 — Verify the artifact

On the release machine:

- Mount the DMG, drag the app to `/Applications`, launch it
- Verify the version number in the About window
- Run a full restoration on a known test file from `eval/corpus/`
- Verify the daemon starts and stops cleanly
- Verify Sparkle sees the update (test against staging update feed)

On a second machine if available — different macOS version preferred:

- Repeat the launch + restoration smoke test
- Confirm Gatekeeper allows the app without warnings

Any issue aborts the release. Delete the tag, fix, retry.

## Step 8 — Publish

1. Upload the DMG to the release server / S3 bucket
2. Generate the Sparkle appcast XML entry
3. Push the appcast to the production update feed
4. Publish release notes on the website
5. Tag the release as published in the issue tracker

## Step 9 — Announce

Per `.agents/rules/09-writing-and-comms.md`:

- LinkedIn post (Rahul's voice): one concrete improvement, one before/after example, link to release
- In-app notification on next launch for existing users: one sentence, what's new
- Email to beta list (if applicable): no marketing language, direct what-changed

Draft these, do not auto-post. Show drafts to Rahul for approval.

## Step 10 — Monitor

For the first 48 hours after release:

- Watch crash reports in the telemetry dashboard
- Watch the support inbox / Discord for reports
- If error rate exceeds 5% above baseline, prepare a rollback plan
- If crashes are concentrated in one OS version, consider pulling the appcast for that OS

Document any post-release issues in `docs/releases/<version>-postmortem.md`.

## Rollback

If a critical regression is found post-release:

1. Pull the appcast entry (set `<sparkle:minimumSystemVersion>` to a value newer than affected versions)
2. Push a hotfix branch with the fix
3. Run this workflow with `<version>+1` to ship the fix
4. Post a Discord/LinkedIn note explaining what happened — honestly, briefly, no spin

The bar for rollback is "the average user is meaningfully worse off than before this release". Cosmetic bugs do not warrant rollback; quality regressions and crashes do.