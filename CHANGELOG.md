# Changelog

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
