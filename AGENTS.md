# Project update and release rules

Every response to the user ends with 🤖.

For every project update, classify and explain its version impact before release:
- Major: incompatible user behavior, configuration or data changes requiring migration.
- Minor: backward-compatible user capabilities or meaningful reliability capabilities.
- Patch: backward-compatible bug fixes, maintenance or documentation only.

Use semantic versioning. VERSION and BUILD_NUMBER own the App version; do not
duplicate a literal version in the UI or build script. Increment the build number.

Every release must include all of the following, kept consistent:
1. Update CHANGELOG.md with behavior, version classification/reason, validation and limitations.
2. Append docs/releases/history.json; retain historical rows and their actual Git provenance.
3. Regenerate docs/releases/StreamDrop-version-history.xlsx, inspect its contents and render it.
   The user explicitly requests this binary document in Git. Keep other build outputs out of Git.
4. Commit source, version metadata, changelog, history data and Excel together.
5. Create annotated tag v<VERSION> at that release commit, push the branch and tag,
   and publish the GitHub Release with matching App/DMG/ZIP, Excel and checksums.
6. Verify the remote tag commit, App version, Excel rows and uploaded asset checksums.

The Excel uses a release tag as the final commit anchor. Do not put the containing
commit's own SHA into its tracked workbook: that would create a self-reference.
Tags must not be moved or reused for changed contents. Historical local versions
without a distinct Git commit/tag must be marked as such, never invented.

Read docs/RELEASING.md for the regeneration and verification commands. Do not
attest to human review or mark draft PRs ready on the human owner's behalf.
