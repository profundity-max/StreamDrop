# Changelog

## 1.2.2 — 2026-10-20

**Patch release.** Update project documentation and App copy without changing
download behavior, settings or stored data.

- Rewrite the README around StreamDrop's purpose, capabilities, installation,
  external tools, everyday use, privacy and development workflow.
- Remove unnecessary third-party affiliation statements from About, Help, Privacy,
  the bundled README and bundle copyright text. Describe StreamDrop directly.
- Synchronize the README to the repository's default branch for the GitHub homepage;
  current implementation remains on the existing development branch and release tags.

Validation: release-record gates, universal App build, signature/package checks and
installed-App copy review. No new download-engine behavior or site coverage.

## 1.2.1 — 2026-10-20

**Patch release.** Correct CI fixture startup and diagnostics without changing App
behavior or user data. The published 1.2.0 tag is retained.

- Use the runner's system Python for verification, matching the locally verified
  interpreter family instead of an ambient Homebrew Python.
- Allow up to 30 seconds for fixture readiness, report elapsed startup time and
  process identity, fail immediately if a fixture exits, and use unbuffered logs.

The first 1.2.0 hosted run timed out waiting for loopback port 18764 after five
seconds; its server log was empty. That establishes a startup failure, not its
underlying cause. This release makes startup bounded and diagnosable and reruns
the complete workflow. Local strict suite and completion/tool coverage remain
required; final hosted results are linked from the GitHub Release.

## 1.2.0 — 2026-10-20

**Minor release.** Add compatible tool-health and diagnostic capabilities, and
strengthen graceful shutdown. Existing preferences and history need no migration.

- Wait for download, converter and version-check resources to settle before normal
  App termination; prevent new transfers during shutdown instead of quitting after
  an eight-second deadline.
- Run bounded yt-dlp/FFmpeg version checks from settings. Distinguish missing tools,
  execution errors, unrecognized output, cancellation and timeout.
- Include App/macOS and currently observed tool versions/paths in copied error
  diagnostics, keeping download errors and original URLs intact.
- Add GitHub Actions verification with required media tools, release-record gates,
  universal build and package checks. Structured XCTest events make skipped or
  missing coverage fail strict mode.
- Cover final completion-state save and receipt-delete failures without restoring
  user-deleted history.

Validation and execution scope are recorded in docs/verification.md. Tests use
owned local fixtures; normal shutdown is distinct from force quit or power loss.
No new public-site or macOS 13 hardware validation; App remains ad-hoc signed.

## 1.1.2 — 2026-10-20

**Patch release.** Correct existing storage, naming and release-record behavior;
existing user data remains readable and requires no migration.

- Let the storage session enforce write permission across saves, completion and
  recovery; preserve unreadable or future-version state without starting downloads.
- Recover a pending completion before restarting its transfer. Retain the receipt
  through final cleanup saves, without restoring user-deleted history.
- Reserve filename space for extensions and collision numbers before shortening
  long titles; use a conservative UTF-8 budget for the destination directory.
- Keep release checks active under optimized Python and derive workbook notes from
  the release record, with independent cell verification.

Validation: 31 XCTest cases, including real local HTTP/HLS/yt-dlp/FFmpeg flows,
storage recovery and actual long-name writes; 3 Python release-gate tests in normal
and optimized interpreters. No new public-site, cross-volume interruption, power-loss,
Intel or macOS 13 hardware validation. App remains ad-hoc signed, not notarized.

## 1.1.1 — 2026-10-19

**Patch release.** Correct webpage download filenames without changing existing history or files.

- Preserve Unicode titles and spaces instead of forcing ASCII filenames.
- Remove the automatically appended bracketed extractor ID. Keep brackets that belong to the title.
- Retain collision numbering so downloads with the same title never overwrite each other.

Validation: real local yt-dlp downloads of a Chinese title with spaces and natural brackets, twice to verify collision safety. Full suite: 27 tests. Existing filenames are retained; filesystem sanitation and length limits still apply.

## 1.1.0 — 2026-10-18

**Minor release.** Recoverable completion and saved playback observations add
backward-compatible capabilities. Existing preferences and download history remain
readable. The unreleased 1.0.3 development build is included in this release.

- Centralize download execution stop intent, terminal delivery and resource completion.
- Recover interrupted file placement/state saves using retained completion receipts and file identity.
- Retry failed cleanup without hiding saved downloads or restoring user-deleted history.
- Preserve decoded, converted, unknown and unchecked playback observations in downloads and history.
- Add cumulative Excel version history, a single App version source and release consistency checks.

Validation: 26 XCTest cases passed in the architecture update, including real local
HTTP/HLS/VP9 flows, native frame decoding and disk failure/recovery cases. Universal
arm64/x86_64 build, strict signature and DMG checks are rerun for this release.

Limits: no new public-site, Intel or macOS 13 hardware validation. If a cross-volume
move stops before its placed identity is recorded, recovery preserves evidence and
reports unknown ownership. Frame sampling does not validate the whole video/audio.
App uses ad-hoc signing; no Developer ID notarization.

## 1.0.3 — development only

Three architecture changes, originally numbered as a patch during development.
Reclassified as 1.1.0 before the first tagged release. Source: 1df7162 and its two
preceding architecture commits. No separate 1.0.3 release or tag was published.

## 1.0.2 — initial Git snapshot

Native playback compatibility checking and H.264 conversion, including cancellation
and pause regression coverage. 21 tests passed. Git snapshot: 1fba35d.

## 1.0.1 — local version

Prioritize real download errors over version warnings, preserve diagnostic details,
and measure final output size. 18 tests passed. No standalone Git commit/tag exists.

## 1.0.0 — local version

Initial native macOS download workflow, queue, history, settings and guided browser.
15 tests passed. No standalone Git commit/tag exists.
